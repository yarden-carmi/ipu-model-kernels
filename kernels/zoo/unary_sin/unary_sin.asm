{#- unary_sin.asm -- y = sin(x) elementwise over numel elements in 128-lane rows,
    ONE parameterised program for every numel: the rows are a dynamic loop whose
    bound is a CR, so a whole call is one launch and the host tiles nothing but
    numel.

    x and y are the plain activation layout (row r holds lanes 128r .. 128r+127,
    lanes past numel zero), so this kernel reads the rows the previous kernel
    wrote and writes the rows the next one reads, with no repack between them.
    The lanes past numel hold 0 in x; their s and p lanes are 0 and the poly of
    0 is c4, but x = 0 there, so the product is 0 and every store names only the
    live lanes with its DS half, writing them 0 for whatever reads y next.

    Hardware-clean NX8: every store is an ACTIVATE.QUANTIZE (identity, or the
    prologue's exp2(0) ones row) and no emulator-only instruction appears. The
    AaQ activates into memory, never back into R_ACC, so every value that has to
    become a multiplicand leaves and comes back as an NX8 row; the passes below
    are exactly those round trips.

    sin is odd, so the program factorises x out: s = x * x and
    sin(x) = x * p(s), p(s) = c4 s^4 + c3 s^3 + c2 s^2 + c1 s + c0, the degree-9
    odd Taylor polynomial of sin. p runs as Horner over s exactly like unary_cos
    runs cos (the sign is in the coefficients, no |x| pass), and one final
    product with the resident x row (cyclic slot 0, held all row) finishes it.

      s = x * x    MULT.RC.VS of the cyclic window (slot 0), identity store.
      p = poly(s)  Horner, dyadic coefficients c4..c1 (the MULT constant's
                   width; c0 = CR1 = 1.0): p starts at c4 (MULT.EE off
                   R0[0] = 1.0, the ones row the prologue stores itself with
                   exp2(0) -- the host prepares no constant), then four steps
                   p = p * s + ck: the product is MULT.RC.VV (s in cyclic slot
                   1, p in R1), the constant is one more MULT_RES (MULT.EE off
                   the ones row) and the row is stored after the add. The
                   intermediate p rows live in y's region -- y is written only
                   by the last store of each row -- so the call takes
                   3*rows + 2 XMEM rows.
      y = x * p    MULT.RC.VV of slot 0 (x) by R1 (p read back), one round trip.

    The last row of a call is usually short (numel - 128*(rows-1) lanes): the
    loop runs the full rows only and the last row is emitted straight-line with
    its own DS half (as is the row before it), so every store's scale comes from
    the row's live lanes.

    Timing contract: LOAD reads LRs after the same word's LR writes, so LR2 (the
    load walk) and LR3 (the store walk) advance in the body's last word, after
    every load has used them; MULT reads R0/R1/R_CYCLIC at word start, so every
    load is at least one word ahead of the multiply that consumes it; ACC takes
    this word's MULT_RES and ACTIVATE.QUANTIZE this word's R_ACC, so multiply,
    accumulate and store share a word; the branch reads cycle-start LRs, so
    BLT.S LR2 LR5 names the row just processed. LR0 is zero (also every
    MULT.RC.*'s mask_shift: shift 0 keeps every lane of the DS partition
    active -- the LR values clamp to [-3, +3], so anything else would mask
    lanes off), LR1 is 128 (cyclic slot 1), R_MASK is loaded from its own
    all-ones row and every accumulation is seeded with a .FIRST form, so the
    program runs after another kernel as well as from reset.

    Cost: 18 words per row, 11 of them multiplying (the four Horner steps are
    two multiplies each, plus the final x * p). 16384 elements is 2312 cycles.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{#- ------------------- one row: square, Horner, times x ------------------------ -#}
{% macro body(dsx, incs, branch) -%}
    LD.MULT.CYCLIC LR2 {{ cr.x }} LR0 ;;                 {#- x[row] -> cyclic slot 0 (held: the final multiply) -#}
    MULT.RC.VS LR0 0 LR0 {{ dsx }} {{ qfl }} ;           {#- s = x^2 -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.s }} LR3 ;;
    MULT.EE LR0 {{ cr.c4 }} 0 LR0 {{ dsx }} {{ qfl }} ;  {#- p = 1.0 * c4 (R0[0] = 1.0) -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3 ;;
    LD.MULT.CYCLIC LR2 {{ cr.s }} LR1 ;;                 {#- s[row] -> cyclic slot 1 -#}
    LD.MULT R1 LR2 {{ cr.y }} ;;                         {#- p -> R1 (Ra's upper half) -#}
    MULT.RC.VV LR1 R1 0 LR0 {{ dsx }} {{ qfl }} ;        {#- p * s -#}
    ACC.ADD.FIRST ;;
    MULT.EE LR0 {{ cr.c3 }} 0 LR0 {{ dsx }} {{ qfl }} ;  {#- + c3 -#}
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3 ;;
    LD.MULT R1 LR2 {{ cr.y }} ;;
    MULT.RC.VV LR1 R1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    MULT.EE LR0 {{ cr.c2 }} 0 LR0 {{ dsx }} {{ qfl }} ;  {#- + c2 -#}
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3 ;;
    LD.MULT R1 LR2 {{ cr.y }} ;;
    MULT.RC.VV LR1 R1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    MULT.EE LR0 {{ cr.c1 }} 0 LR0 {{ dsx }} {{ qfl }} ;  {#- + c1 -#}
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3 ;;
    LD.MULT R1 LR2 {{ cr.y }} ;;
    MULT.RC.VV LR1 R1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }} ;          {#- + c0 = CR1 -#}
    ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3 ;;
    LD.MULT R1 LR2 {{ cr.y }} ;;                         {#- p -> R1 -#}
    MULT.RC.VV LR0 R1 0 LR0 {{ dsx }} {{ qfl }} ;        {#- y = x * p (slot 0 still holds x) -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3 ;;
{% if incs %}    INC LR2 1 ; INC LR3 1{% if branch %} ;
    BLT.S LR2 LR5 row_loop ;;{% else %} ;;{% endif %}
{% endif %}
{%- endmacro %}

    SET LR0 CR0 ; LD.MASK LR0 {{ cr.maskr }} ;;           {#- 0: slot 0, the mask shift, MULT.EE's element -#}
    SET LR1 {{ cr.slot1 }} ; SET LR2 CR0 ;;               {#- cyclic slot 1; the load walk -#}
    SET LR3 CR0 ; SET LR5 {{ cr.bound }} ;;               {#- the store walk; the loop's bound -#}
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;                  {#- a row (any) into slot 0 -#}
    MULT.RC.VE LR0 CR0 0 LR0 {{ dsf }} {{ qfl }} ;        {#- 0 * x: every lane 0, so exp2 gives 1.0 -#}
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE exp2 {{ dsf }} {{ qfl }} {{ cr.one }} LR3 ;;
    LD.MULT R0 LR0 {{ cr.one }} ;;                        {#- the ones row -> R0: MULT.EE's source -#}
{% if main >= 2 %}
row_loop:
{{ body(dsf, true, true) }}                               {#- the full rows but the last -#}
{% endif %}
{% if main >= 1 %}
{{ body(dsf, hastrail, false) }}                          {#- the last full row (walks on to the tail) -#}
{% endif %}
{% if hastrail %}
{{ body(dsl, false, false) }}                             {#- the short last row, its own DS -#}
{% endif %}
end:
    HALT ;;
