{#- binary_add_row.asm -- y = a (op) b elementwise with b broadcast as a ROW:
    b holds `inner` values and its rows repeat over a's rows, so
    y[i] = a[i] op b[i mod inner].

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are ceil(numel/128) rows each, row i holding elements
    128i .. 128i+127, lanes past numel zero. b is ceil(inner/128) rows, row j
    holding elements 128j .. 128j+127, and it repeats: a row r is combined with
    b row (r mod b_rows). This is exact -- no lane rotation -- whenever inner is
    a multiple of 128, which the domain requires; `inner` is further restricted
    to values whose row count is a power of two, so the b row pointer wraps with
    INC.MODP2 and never needs a compare-and-reset word.

    Dataflow and timing contract are exactly binary_add_none's: an operand in
    XMEM costs a LOAD and a word has one LOAD slot, so a row costs two words and
    both run the multiplier. Word A multiplies the b row resident in R1 by the
    CR constant 1.0 and initialises the accumulator with it; word B multiplies
    the a row resident in R0 by 1.0, accumulates and stores the row; each word
    loads the row the *next* word multiplies. `mul` is one product per row
    (the cyclic a row against the resident b row), its second word carrying
    only the b load. The b pointer LR2 advances with INC.MODP2 LR2 LR6 k
    (LR6 = 1, k = log2(b_rows)) instead of INC.

    LR: LR0 0; LR2 the b row pointer (mod b_rows); LR3 the y row being stored;
    LR4 the row loop's bound; LR5 the a row pointer; LR6 1 (the MODP2 step);
    LR11 128 (R1's element offset in Ra). The program sets every LR it reads
    and loads its own mask row, so it runs after another kernel as well as
    from reset.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set main = rows - (1 if hastrail else 0) %}
{% set brows = (inner + 127) // 128 %}
{% set k = brows.bit_length() - 1 %}
{#- a single b row needs no pointer move at all: mod 1 is 0, and INC.MODP2's
    k immediate starts at 1 -#}
{% set stepb = "INC.MODP2 LR2 LR6 " ~ k if k > 0 else "" %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{% set A1 = {"add": "ACC.ADD.FIRST", "sub": "ACC.SUB.FIRST", "max": "ACC.MAX.FIRST"}[op] %}
{% set A2 = {"add": "ACC.ADD", "sub": "ACC.ADD", "max": "ACC.MAX"}[op] %}
{% macro body2(dsx, loads, branch) -%}
    MULT.VE LR11 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A1 }} ;
    INC LR3 1{% if loads %} ;
    {{ stepb }}{% if stepb %} ;{% endif %}
    LD.MULT R1 LR2 {{ cr.b }} ;;{% else %} ;;{% endif %}
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
    INC LR5 1 ;
    LD.MULT.CYCLIC LR5 {{ cr.a }} LR0 ;;
    {{ stepb }}{% if stepb %} ;{% endif %} INC LR3 1 ;
    LD.MULT R1 LR2 {{ cr.b }}{% if branch %} ;
    BLT.S LR5 LR4 row_loop ;;{% else %} ;;{% endif %}{% else %} ;;{% endif %}
{%- endmacro %}
{% set body = bodymul if op == "mul" else body2 %}

    SET LR0 CR0 ; SET LR11 {{ cr.slot1 }} ; SET LR6 CR1 ;;   {#- 0; R1's offset; MODP2 step -#}
    SET LR2 CR0 ; SET LR5 CR0 ;;                          {#- the b and a row pointers -#}
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
    LD.MULT R1 LR2 {{ cr.b }} ;;                          {#- prime: b row 0 -> R1 -#}
{% if main >= 2 %}
row_loop:
{{ body(dsf, true, true) }}                               {#- the full rows, two words each -#}
{% endif %}
{% if main >= 1 %}
{{ body(dsf, hastrail, false) }}                          {#- the last full row (it loads the short one) -#}
{% endif %}
{% if hastrail %}
{{ body(dsl, false, false) }}                             {#- the short last row, its own DS -#}
{% endif %}
end:
    HALT ;;
