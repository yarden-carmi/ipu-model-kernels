{#- unary_log.asm -- y = log(x) elementwise, one parameterised program.

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): x and y are ceil(numel/128) rows each, row i holding elements
    128i .. 128i+127, lanes past numel zero -- the layout every activation on
    the chip uses, so y is the next kernel's input.

    The substitution u = x - 1.25 (dyadic constants: the scale is CR1's 1.0,
    the offset enters as a MULT.EE off the ones row) keeps |u| <= 0.75 over the
    declared input range [0.5, 2], where the degree-3 monomial

        y = b0 + b1 u + b2 u^2 + b3 u^3            (b's in CR10..CR13)

    is within a fraction of the output grid of log. The multiplier's only
    operands are the LOAD-filled stages (R0, R1, R_CYCLIC), so every serial
    dependence of the polynomial is one NX8 row round trip: u (stored word 3,
    reloaded into R0 and R_CYCLIC), u2 = MULT.RC.VS of the cyclic window
    (stored, reloaded), u3 = MULT.RC.VV of u2 against R0 = u (stored,
    reloaded). The sum itself is pure FP32 registers: seeded with b0
    (MULT.EE off R1[0] = 1.0 -- R1 is the prologue's own exp2(0) ones row, so
    the host prepares no constant) once the ladder has finished with R_ACC,
    then b3 u3, b2 u2 and b1 u accumulate and the row is stored with identity.

    Timing contract: the Control stage (LR writes, branch) reads LRs at cycle
    start; LOAD/MULT/ACC/AAQ read them after the same word's writes. Hence
    LR5 (the x row pointer) is incremented in the word whose LOAD reads the
    new value, LR3 (the row every store of this row writes, and the u/u2/u3
    loads read) is incremented in the NEXT body's first word, and the loop's
    branch reads LR5 as it was when the word began -- one behind, so LR4 is
    the last index that still loops minus one. LR3 starts at -1 (SET CR0,
    DEC 1) so the first body's INC lands on row 0.

    LR: LR0 0; LR3 the row being stored (starts -1); LR4 the loop's bound;
    LR5 the x row pointer; LR11 128 (R1's element offset in Ra). The program
    sets every LR it reads and loads its own mask row, so it runs after another
    kernel as well as from reset.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{#- One row: 14 words. `nxt` loads the following row into R0 (and bumps LR5 in
    the word before it, so the load reads the bumped pointer); `branch` closes
    the row loop. -#}
{% macro body(dsx, inc, load_next, branch) -%}
    INC LR3 1 ; LD.MULT R0 LR5 {{ cr.x }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD.FIRST ;;
    MULT.EE LR11 {{ cr.c }} 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.u }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.u }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.u }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.p2 }} LR3 ;;
    LD.MULT.CYCLIC LR3 {{ cr.p2 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.p3 }} LR3 ;;
    LD.MULT.CYCLIC LR3 {{ cr.p3 }} LR0 ;;
    MULT.EE LR11 {{ cr.b0 }} 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{ cr.b3 }} 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD ;
    LD.MULT.CYCLIC LR3 {{ cr.p2 }} LR0 ;;
    MULT.RC.VE LR0 {{ cr.b2 }} 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD ;;
    MULT.VE LR0 {{ cr.b1 }} 0 LR0 {{ dsx }} {{ qfl }} ; ACC.ADD{% if inc %} ;
    INC LR5 1 ;;{% else %} ;;{% endif %}
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3{% if branch %} ;
    LD.MULT R0 LR5 {{ cr.x }} ;
    BLT.S LR5 LR4 row_loop ;;{% elif load_next %} ;
    LD.MULT R0 LR5 {{ cr.x }} ;;{% else %} ;;{% endif %}
{%- endmacro %}

    SET LR0 CR0 ;;                                        {#- the zero index -#}
    SET LR11 CR0 ;;
    INC LR11 128 ;;                                       {#- R1's element offset in Ra -#}
    SET LR5 CR0 ; SET LR3 CR0 ;;                          {#- x pointer; store row -#}
    DEC LR3 1 ;;                                          {#- the first INC lands on row 0 -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
    MULT.RC.VE LR0 CR0 0 LR0 {{ dsf }} {{ qfl }} ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE exp2 {{ dsf }} {{ qfl }} {{ cr.one }} LR0 ;;   {#- one <- exp2(0) = 1 -#}
    LD.MULT R1 LR0 {{ cr.one }} ;;                        {#- R1: the ones row every MULT.EE broadcasts from -#}
{% if main >= 2 %}
    SET LR4 CR0 ;;                                        {#- the loop's bound: main - 1 -#}
    {%- for _ in range((main - 1) // 255) %}
    INC LR4 255 ;;
    {%- endfor %}
    INC LR4 {{ (main - 1) % 255 }} ;;
{% endif %}
{% if main >= 2 %}
row_loop:
{{ body(dsf, true, true, true) }}                         {#- rows 0 .. main-2, one row ahead loaded -#}
{% endif %}
{% if main >= 1 %}
{{ body(dsf, true, hastrail, false) }}                    {#- the last full row (it loads the short one) -#}
{% endif %}
{% if hastrail %}
{{ body(dsl, false, false, false) }}                      {#- the short last row, its own DS -#}
{% endif %}
end:
    HALT ;;
