{#- binary_sub_row.asm -- y = a (op) b elementwise with b broadcast as a row.

    Layout: a and y are ceil(numel/128) rows each, row i holding elements
    128i..128i+127, lanes past numel zero. b is ONE row of `inner` values
    (1..128), lanes past `inner` zero, and every row of a combines with that
    same row: y row i = a row i (op) b row 0. b is loaded once into R1 and
    stays resident, so its pointer never moves.

    Dataflow, per row: a row costs a LOAD, a word has one LOAD and one MULT
    slot, and a subtract needs two multiplies (the only way into R_ACC is
    MULT_RES), so add/sub/max are two words per row: word A multiplies the
    resident b row by the CR constant 1.0 and initialises the accumulator
    (ACC.ADD/SUB/MAX.FIRST -- for sub this lands -b in R_ACC), word B
    multiplies the a row resident in R0 by 1.0, accumulates (ACC.ADD /
    ACC.ADD / ACC.MAX) and stores the row; each word loads the a row the next
    word multiplies. A row of `mul` is one product a*b (MULT.RC.VV of the
    cyclic a row against the resident b row), so its word carries the store
    and the next a load; the store and its counter step live in different
    words (a sub-slot that writes a register and the AAQ store that reads it
    do not share a word), so mul keeps the two-word shape with the counter and
    branch in the second word.

    The last row of a call is short (numel - 128*(rows-1) lanes) and is
    emitted straight-line with its own DS half, as is the row before it, which
    keeps the one-row-ahead loads inside the regions.

    LR: LR0 0; LR3 the y row being stored; LR4 the row loop's bound; LR5 the
    a row pointer; LR6 a copy of the a pointer the branch reads; LR11 128
    (R1's element offset in Ra). The program sets every LR it reads and loads
    its own mask row, so it runs after another kernel as well as from reset.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{% set A1 = {"add": "ACC.ADD.FIRST", "sub": "ACC.SUB.FIRST", "max": "ACC.MAX.FIRST"}[op] %}
{% set A2 = {"add": "ACC.ADD", "sub": "ACC.ADD", "max": "ACC.MAX"}[op] %}
{% macro body2(dsx, loads, branch) -%}
    MULT.VE LR11 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A1 }} ;
    INC LR3 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A2 }} ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3{% if loads %} ;
    INC LR5 1 ;
    LD.MULT R0 LR5 {{ cr.a }}{% if branch %} ;
    BLT.S LR5 LR4 row_loop ;;{% else %} ;;{% endif %}{% elif branch %} ;
    BLT.S LR5 LR4 row_loop ;;{% else %} ;;{% endif %}
{%- endmacro %}
{% macro bodymul(dsx, loads, branch) -%}
    MULT.RC.VV LR0 R1 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR3{% if loads %} ;
    ADD LR6 LR5 CR0 ;
    INC LR5 1 ;
    LD.MULT.CYCLIC LR5 {{ cr.a }} LR0 ;;
    INC LR3 1{% if branch %} ;
    BLT.S LR6 LR4 row_loop ;;{% else %} ;;{% endif %}{% elif branch %} ;
    BLT.S LR6 LR4 row_loop ;;{% else %} ;;{% endif %}
{%- endmacro %}

    SET LR0 CR0 ; SET LR11 {{ cr.slot1 }} ;;              {#- 0; R1's element offset in Ra -#}
    SET LR5 CR0 ;;                                        {#- the a row pointer -#}
    SET LR3 CR0 ;;
{% if op != "mul" %}
    DEC LR3 1 ;;                                          {#- the row being stored, one behind -#}
{% endif %}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
{% if main >= 2 %}
    SET LR4 {{ cr.bound }} ;;                             {#- the last index that still loops -#}
{% endif %}
{% if op == "mul" %}
    LD.MULT.CYCLIC LR5 {{ cr.a }} LR0 ;;                  {#- prime: a[0] -> R_CYCLIC[0..127] -#}
{% else %}
    LD.MULT R0 LR5 {{ cr.a }} ;;                          {#- prime: a[0] -> R0 -#}
{% endif %}
    LD.MULT R1 LR0 {{ cr.b }} ;;                          {#- the broadcast row, resident for the whole call -#}
{% if main >= 2 %}
row_loop:
{% if op == "mul" %}
{{ bodymul(dsf, true, true) }}                            {#- the full rows, two words each -#}
{% else %}
{{ body2(dsf, true, true) }}                              {#- the full rows, two words each -#}
{% endif %}
{% endif %}
{% if main >= 1 %}
{% if op == "mul" %}
{{ bodymul(dsf, hastrail, false) }}                       {#- the last full row (it loads the short one) -#}
{% else %}
{{ body2(dsf, hastrail, false) }}                         {#- the last full row (it loads the short one) -#}
{% endif %}
{% endif %}
{% if hastrail %}
{% if op == "mul" %}
{{ bodymul(dsl, false, false) }}                          {#- the short last row, its own DS -#}
{% else %}
{{ body2(dsl, false, false) }}                            {#- the short last row, its own DS -#}
{% endif %}
{% endif %}
end:
    HALT ;;
