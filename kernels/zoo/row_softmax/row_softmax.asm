{#- row_softmax.asm -- y[r, :] = softmax(x[r, :]) for each row of a (rows, n)
    matrix, one parameterised program for every (rows, n): the row loop is
    dynamic and the row's 128-lane chunks are a rendered per-call unroll, so
    the shape reaches the program only through CRs and one launch takes a
    whole (rows, n) tile -- the host tiles `rows` across launches.

    The exp2 recipe (max, exp2, sum, reciprocal), four passes over the row,
    streamed chunk by chunk through R_CYCLIC slot 0 (the next chunk's load
    rides in the word that multiplies the current one, per the timing
    contract: a LOAD reads LRs after the same word's LR writes, and MULT
    reads R_CYCLIC as the word began, so a load into the window a word
    multiplies lands one word later than it is needed -- i.e. exactly when
    the next word multiplies it):

      pass 1  the row's largest element. One word per chunk multiplies the
              x chunk by the CR constant 1.0 and AGG.MAXes it into R_ACC
              slot 0 (the first chunk seeds it, the rest take the running
              max); the last chunk's word is also the store, and it is a
              `relu` store: the AaQ floors the max at 0, so a row whose
              logits are all negative shifts by 0 instead of by a negative
              amount, which is what keeps pass 2's argument <= 0 (exp2 of a
              positive input is an AaQ error). max needs no |.|: the shift
              only has to dominate c * max(x), and 2 * max(x, 0) does. The
              same word reloads x's chunk 0 into slot 0, which is where
              pass 2 wants it.
      pass 2  num = exp2(c*x - 2*max) chunk by chunk, two words per chunk:
              the first multiplies the resident x chunk by c1 then by c2
              (c = log2(e) as two exactly representable dyadic terms, one
              MULT each, because an NX8 MULT constant holds at most 7
              significant bits and a single one would move the temperature
              -- and every probability with it -- by 4e-2 relative), the
              second subtracts 2 * max (MULT.EE of the scalar in R1[0],
              which chunk 0's first word loaded) and ACTIVATE.QUANTIZE
              exp2-stores the numerator into a y row -- there is no
              numerator region: 2 * rows * tiles rows is all a call owns,
              and pass 4 overwrites these rows with the probabilities. The
              argument is <= (c - 2) * max <= 0 in every lane; a row-common
              shift cancels in the normalisation, so only its sign matters.
              The last chunk's word primes pass 3: it loads the numerator's
              chunk 0 (a separate word when tiles == 1, where that row is
              the store's own).
      pass 3  sum = AGG.SUM of the numerator chunks into R_ACC slot 0, one
              word per chunk, streamed like pass 1 -- except the LAST
              chunk, which word tiles - 2 parks in slot 1 and its own word
              multiplies from there: the last chunk's row is the scalar
              row (y's own last row), and pass 4 must not reload it after
              the reciprocal has landed there. The last chunk's word is
              also ACTIVATE.QUANTIZE reciprocal, so the scalar row's lane 0
              holds 1/sum, which the next word's LOAD reads into R0[0].
      pass 4  y = num * rinv (MULT.RC.VE with the scalar named by LR0, Ra
              element 0 = R0[0]), ACC.ADD.FIRST and ACTIVATE.QUANTIZE
              identity in the same word -- one word per chunk, streamed
              through slot 0, the last chunk again from slot 1. The store
              rows walk two LRs (LR8 the even chunks, LR9 the odd ones):
              an ACTIVATE's table_offset is a forwarded read, so a walk it
              names is stepped in the *previous* chunk's word, one walker
              behind the other. The last chunk's word is also the row
              loop's: it advances the row base, decrements the counter and
              branches.

    A row is 4 * tiles + 4 words: one prime, tiles for each of passes 1, 3
    and 4 (plus pass 4's chunk-0 load and slot-1 park), two per chunk of
    pass 2, the 1/sum read-back and pass 4's prime.

    Layout: x and y are the plain row-major activation layout (entity e holds
    its n features in tiles = ceil(n / 128) consecutive rows, lanes past n
    zero), which is what the last chunk's DS writes and what the next kernel
    reads. The two scalars round-trip through y's own last row
    (CR11 = rows * tiles - 1): the max is stored there in pass 1 and read
    back through R1 before the numerator of that row replaces it; the 1/sum
    is stored there in pass 3 and read back through R0 before the last
    probability replaces it -- and the last chunk of the last row is never
    re-read from XMEM between those stores (it lives in slot 1), which is
    what makes the round trip safe at every tiles.

    Registers (kernel.toml's [abi]; CR0 = 0 and CR1 = 1 are hardwired):
      cr.x cr.y     the two regions, both ROW numbers; y also carries the
                    numerators and, in its last row, the two scalars
      cr.rows_m1    rows - 1, the row loop's bound (DEC'd, BLT.S against 0)
      cr.c1 cr.c2   log2(e)'s two dyadic terms
      cr.two        the shift's 2
      cr.scratch    rows * tiles - 1, the scalar row's offset inside y
      cr.tiles      tiles: the row loop's stride
      cr.ds1_128    CR13: L = ds(1) (the scalar rows), H = 128 (R1's element
                    offset in Ra, and slot 1's R_CYCLIC index)
      cr.qf         the case's QF half (CR14.L)
      cr.ds_all     CR15: L = ds(128) a full chunk, H = ds(n - 128*(tiles-1))
      LR0 0 (R_CYCLIC slot 0, AGG's destination slot, the mask shift, and
      Ra's R0 element 0 -- pass 4's scalar) ; LR1 128 (Ra's R1 element 0 --
      pass 2's max, and slot 1's R_CYCLIC index) ; LR2 the row counter ;
      LR3 the chunk read walk ; LR6 this row's base row ; LR7 the scalar
      row ; LR8 LR9 the two y-row walkers. The program sets every LR it
      reads, and R_ACC is initialised by the .FIRST aggregate of every
      pass, so it runs after another kernel as well as from reset.
-#}
{% set T = (n + 127) // 128 %}
{% set dall = cr.ds_all ~ ".L" %}
{% set dlast = cr.ds_all ~ ".H" %}
{% set qfl = cr.qf ~ ".L" %}
{% set dsc = cr.ds1_128 ~ ".L" %}
    SET LR0 CR0 ; SET LR1 {{ cr.ds1_128 }}.H ; SET LR6 CR0 ;;   {#- LR1: Ra's R1 element / slot 1 -#}
    SET LR2 {{ cr.rows_m1 }} ; SET LR7 {{ cr.scratch }} ;;

row_loop:
{#- ==================== prime: x's chunk 0 into slot 0 ==================== -#}
    SET LR3 LR6 ;;
    LD.MULT.CYCLIC LR3 {{ cr.x }} LR0 ;;

{#- ================== pass 1: the row's largest element =================== -#}
{% for c in range(T) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ dall }} {{ qfl }} ;
    AGG.MAX{% if c == 0 %}.FIRST{% endif %} LR0 {{ dall }}{% if c == T - 1 %} ;
    ACTIVATE.QUANTIZE relu {{ dsc }} {{ qfl }} {{ cr.y }} LR7 ;
    SET LR8 LR6 ;
    SET LR3 LR6 ;
    LD.MULT.CYCLIC LR3 {{ cr.x }} LR0{% else %} ;
    INC LR3 1 ;
    LD.MULT.CYCLIC LR3 {{ cr.x }} LR0{% endif %} ;;
{% endfor %}

{#- ========= pass 2: num = exp2(c*x - 2*max), stored into y's rows ========
    three words per chunk: c1*x (and the next x chunk's load), then c2*x and
    the max's load into R1, then 2*max subtracted and the row stored. The
    MULT stage reads R0/R1 as the word began, so the max's load is the word
    before the MULT.EE that uses it. -#}
{% for c in range(T) %}
{% if c < T - 1 %}
    INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.x }} LR0 ; MULT.RC.VE LR0 {{ cr.c1 }} 0 LR0 {{ dall }} {{ qfl }} ; ACC.ADD.FIRST{% if c > 0 %} ; INC LR8 1{% endif %} ;;
{% else %}
    MULT.RC.VE LR0 {{ cr.c1 }} 0 LR0 {{ dall }} {{ qfl }} ; ACC.ADD.FIRST{% if T > 1 %} ;
    INC LR8 1 ; SET LR3 LR6 ;
    LD.MULT.CYCLIC LR3 {{ cr.y }} LR0{% endif %} ;;       {#- prime pass 3 with the numerator's chunk 0 -#}
{% endif %}
    MULT.RC.VE LR0 {{ cr.c2 }} 0 LR0 {{ dall }} {{ qfl }} ; ACC.ADD{% if c == 0 %} ;
    LD.MULT R1 LR7 {{ cr.y }}{% endif %} ;;               {#- R1[0] = the row's max, for every MULT.EE -#}
    MULT.EE LR1 {{ cr.two }} 0 LR0 {{ dall }} {{ qfl }} ; ACC.SUB ;
    ACTIVATE.QUANTIZE exp2 {{ dlast if c == T - 1 else dall }} {{ qfl }} {{ cr.y }} LR8 ;;
{% endfor %}
{% if T == 1 %}
    SET LR3 LR6 ; LD.MULT.CYCLIC LR3 {{ cr.y }} LR0 ;;   {#- prime pass 3: the numerator's only chunk -#}
{% endif %}

{#- ==== pass 3: the row's sum, then 1/sum into the scalar row (the last
    chunk parks in slot 1: its row is the scalar's, and pass 4 must not
    re-read it after the reciprocal lands there) ============================ -#}
{% for c in range(T) %}
    {% if c < T - 2 %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.y }} LR0 ; {% elif T > 1 and c == T - 2 %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.y }} LR1 ; {% endif %}MULT.RC.VE {{ "LR1" if T > 1 and c == T - 1 else "LR0" }} CR1 0 LR0 {{ dall }} {{ qfl }} ;
    AGG.SUM{% if c == 0 %}.FIRST{% endif %} LR0 {{ dall }}{% if c == T - 1 %} ;
    ACTIVATE.QUANTIZE reciprocal {{ dsc }} {{ qfl }} {{ cr.y }} LR7{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR7 {{ cr.y }} ;;                         {#- R0[0] = 1/sum -#}
{% if T > 1 %}
    SET LR3 LR6 ; SET LR8 LR6 ; ADD LR9 LR6 CR1 ;
    LD.MULT.CYCLIC LR3 {{ cr.y }} LR0 ;;                 {#- prime pass 4 with the numerator's chunk 0 -#}
{% else %}
    SET LR8 LR6 ;;                                       {#- chunk 0 is resident in slot 0 -#}
{% endif %}

{#- ==================== pass 4: y = num * rinv, streamed ================== -#}
{% for c in range(T) %}
{% set walker = "LR8" if c % 2 == 0 else "LR9" %}
{% set other = "LR9" if c % 2 == 0 else "LR8" %}
    {% if c < T - 2 %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.y }} LR0 ; {% endif %}MULT.RC.VE {{ "LR1" if T > 1 and c == T - 1 else "LR0" }} LR0 0 LR0 {{ dall }} {{ qfl }} ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dlast if c == T - 1 else dall }} {{ qfl }} {{ cr.y }} {{ walker }}{% if c < T - 1 %} ;
    {% if c > 0 %}INC {{ other }} 2{% else %}{% endif %}{% else %} ;
    ADD LR6 LR6 {{ cr.tiles }} ; DEC LR2 1 ; BLT.S CR0 LR2 row_loop{% endif %} ;;
{% endfor %}

end:
    HALT ;;
