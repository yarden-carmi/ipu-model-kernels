{#- row_softmax.asm -- y[r, :] = softmax(x[r, :]) for each row of a (rows, n)
    matrix, one parameterised program for every (rows, n): the row loop is
    dynamic and the row's 128-lane chunks are rendered per call, so the shape
    reaches the program only through CRs and one launch takes a whole call.

    The exp2 recipe (max, exp2, sum, reciprocal), four passes over the row:

      pass 1  the row's largest element. One word per chunk aggregates
              x * 1.0 into R_ACC slot 0 with AGG.MAX (the first chunk seeds it,
              the rest take the running max); the last chunk's word is also the
              store, and it is a `relu` store: the AaQ floors the max at 0, so
              a row whose logits are all negative shifts by 0 instead of by a
              negative amount, which is what keeps pass 2's argument <= 0 (exp2
              of a positive input is an AaQ error). max needs no |.|: the
              shift only has to dominate c * max(x), and 2 * max(x, 0) does.
      pass 2  num = exp2(c*x - 2*max) chunk by chunk, ACTIVATE.QUANTIZE
              exp2-stored into the *y* region -- there is no numerator region:
              2 * rows * tiles rows is all a call owns (the declared domain's
              widest call, 4096 rows at n = 256, uses every one of them), and
              pass 4 overwrites these rows with the probabilities. c = log2(e)
              is the sum of two dyadic terms, one MULT.RC.VE each, so every
              product is exact in the FP32 accumulator: an NX8 MULT constant
              holds at most 7 significant bits, and a single one of them would
              move the temperature -- and every probability with it -- by 4e-2
              relative. The argument is <= (c - 2)*max <= 0 in every lane (the
              scalar's own quantization is 2^-7 relative, nowhere near the
              0.56*max of slack the factor 2 leaves); a row-common shift
              cancels in the normalisation, so only its sign matters.
      pass 3  sum = AGG.SUM of the numerator chunks into R_ACC slot 0; the last
              chunk's word is also ACTIVATE.QUANTIZE reciprocal, so the scalar
              row's lane 0 holds 1/sum, which the next word's LOAD reads into
              R0[0]. Its own quantization is free: it is a factor common to the
              row, and pass 4's output row takes its scale from its own largest
              element.
      pass 4  y = num * rinv (MULT.RC.VE with the scalar named by LR0, Ra
              element 0 = R0[0]), ACC.ADD.FIRST and ACTIVATE.QUANTIZE identity
              in the same word -- one word per chunk.

    R_CYCLIC holds all four windows of the row at once, which is what removes
    every redundant load: the x chunks live in slots 0 and 1 (indices LR0 = 0
    and LR1 = 128) from pass 1 to the end of pass 2, and the numerator chunks
    in slots 2 and 3 (LR4 = 256, LR5 = 384) from pass 3 to the end of pass 4 --
    pass 3 loads them once and pass 4 multiplies them out of the register, so
    the row is read from XMEM exactly as many times as it has to be. The two
    scalar loads ride in words that are otherwise idle in the LOAD slot (the
    max's, in pass 2's first word); only 1/sum's needs a word of its own,
    because it is stored and read back and the LOAD slot runs before the AaQ
    one. A row is thus 9 words at one chunk and 14 at two.

    Pipelining (docs/content/explanation/timing-model.md): a LOAD reads the LRs
    after the same word's LR writes, so the next chunk's load rides in the word
    that multiplies the current one and a walk is stepped by INC in the word
    that names its row; a MULT reads R0/R1/R_CYCLIC as the word began, so a
    load is always at least one word ahead of the multiply that uses it; an ACC
    takes this word's MULT_RES and an ACTIVATE this word's R_ACC, so multiply,
    accumulate and store share a word; an ACTIVATE/AGG LR operand is a
    *forwarded* read, so a walk a store names is never stepped in the store's
    own word (that word would store one row too far) -- the two y rows are
    therefore named by two LRs (LR8, LR9) set once per row; and the LR
    sub-slots and the branch read word-start values, so the row pointer's
    advance and the loop's branch ride in pass 4's last word and the branch
    sees the pre-DEC counter (it ends after exactly `rows` rows).

    Layout: x and y are the plain row-major activation layout (entity e holds
    its n features in tiles = ceil(n / 128) consecutive rows, lanes past n
    zero), which is what the last chunk's DS writes and what the next kernel
    reads. The declared domain is n <= 256, so a row is at most two chunks and
    the four R_CYCLIC slots hold all of it.

    Memory: x is rows*tiles rows and y is rows*tiles, and that is all the
    program owns -- 2 * rows * tiles <= 16384 is exactly what the widest call
    (4096 rows at n = 256) uses, hence the numerator rows living in y and the
    two scalars (the row's max, then its 1/sum) round-tripping through y's own
    last row (CR11 = rows*tiles - 1), which is written last of all and whose
    chunk is already resident in its R_CYCLIC slot when the scalar lands there.

    Registers (kernel.toml's [abi]; CR0 = 0 and CR1 = 1 are hardwired):
      cr.x cr.y     the two regions, both ROW numbers; y also carries the
                    numerators and, in its last row, the two scalars
      cr.rows_m1    rows - 1, the row loop's bound (BLT.S reads the pre-DEC LR2)
      cr.tiles      tiles: LR6's step
      cr.slot2 cr.slot3  256, 384: R_CYCLIC's slot 2 and 3 indices
      cr.scratch    rows*tiles - 1, the scalar row's offset inside y
      cr.c1 cr.two  log2(e)'s first term and the shift's 2
      cr.qf         the case's QF half (CR14.L)
      cr.ds_all     CR15: L = ds(128) a full chunk, H = ds(n - 128*(tiles-1))
      cr.ds1_128    CR13: L = ds(1) (the scalar row), H = 128 (R1's base in Ra)
      LR0 0 (R_CYCLIC slot 0, AGG's destination slot, the mask shift, and Ra's
      R0 element 0 -- pass 4's scalar) ; LR1 128 (slot 1, and Ra's R1 element 0
      -- pass 2's max) ; LR2 the row counter ; LR3 the chunk read walk ;
      LR4 256 (slot 2) ; LR5 384 (slot 3) ; LR6 this row's base row ; LR7 the
      scalar row ; LR8 LR6, LR9 LR6+1: the row's two y rows (the numerators,
      then the probabilities).
-#}
{% set T = (n + 127) // 128 %}
{% set xs = ["LR0", "LR1"] %}
{% set ns = ["LR4", "LR5"] %}
{% set yrow = ["LR8", "LR9"] %}
{% set last = T - 1 %}
    SET LR0 CR0 ; SET LR1 CR13.H ; SET LR4 {{ cr.slot2 }} ;;
    SET LR5 {{ cr.slot3 }} ; SET LR7 {{ cr.scratch }} ; SET LR6 CR0 ;;
    SET LR2 {{ cr.rows_m1 }} ;;

row_loop:
{#- ================= pass 1: the row's largest element -> the scalar row ==== -#}
    SET LR3 LR6 ; SET LR8 LR6 ; ADD LR9 LR6 CR1 ;
    LD.MULT.CYCLIC LR3 {{ cr.x }} {{ xs[0] }} ;;
{% for c in range(T) %}
    MULT.RC.VE {{ xs[c] }} CR1 0 LR0 CR15.L CR14.L ; AGG.MAX{% if c == 0 %}.FIRST{% endif %} LR0 CR15.L ;
    {% if c == 0 and T > 1 %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.x }} {{ xs[1] }}{% endif %}
    {% if c == last %}ACTIVATE.QUANTIZE relu CR13.L CR14.L {{ cr.y }} LR7{% endif %} ;;
{% endfor %}

{#- ============ pass 2: num = exp2(c*x - 2*max), stored into y's rows ======= -#}
{% for c in range(T) %}
    MULT.RC.VE {{ xs[c] }} {{ cr.c1 }} 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;
    {% if c == 0 %}LD.MULT R1 LR7 {{ cr.y }}{% endif %} ;;
    MULT.RC.VE {{ xs[c] }} {{ cr.c2 }} 0 LR0 CR15.L CR14.L ; ACC.ADD ;;
    MULT.EE LR1 {{ cr.two }} 0 LR0 CR15.L CR14.L ; ACC.SUB ;
    ACTIVATE.QUANTIZE exp2 {% if c == last %}CR15.H{% else %}CR15.L{% endif %} CR14.L {{ cr.y }} {{ yrow[c] }} ;
    {% if c == last and T > 1 %}SET LR3 LR6 ; LD.MULT.CYCLIC LR3 {{ cr.y }} {{ ns[0] }}{% endif %} ;;
{% endfor %}
{% if T == 1 %}
    SET LR3 LR6 ; LD.MULT.CYCLIC LR3 {{ cr.y }} {{ ns[0] }} ;;
{% endif %}

{#- ============ pass 3: the row's sum, then 1/sum into the scalar row ====== -#}
{% for c in range(T) %}
    MULT.RC.VE {{ ns[c] }} CR1 0 LR0 CR15.L CR14.L ; AGG.SUM{% if c == 0 %}.FIRST{% endif %} LR0 CR15.L ;
    {% if c == 0 and T > 1 %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.y }} {{ ns[1] }}{% endif %}
    {% if c == last %}ACTIVATE.QUANTIZE reciprocal CR13.L CR14.L {{ cr.y }} LR7{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR7 {{ cr.y }} ;;

{#- ==================== pass 4: y = num * rinv, out of the slots =========== -#}
{% for c in range(T) %}
    MULT.RC.VE {{ ns[c] }} LR0 0 LR0 CR15.L CR14.L ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {% if c == last %}CR15.H{% else %}CR15.L{% endif %} CR14.L {{ cr.y }} {{ yrow[c] }} ;
    {% if c == last %}ADD LR6 LR6 {{ cr.tiles }} ; DEC LR2 1 ; BLT.S CR0 LR2 row_loop{% endif %} ;;
{% endfor %}

end:
    HALT ;;
