{#- binary_add_none.asm -- y = a (op) b elementwise, one parameterised program
    for every (op, numel) of the kernel's domain.

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are ceil(numel/128) rows each, row i holding elements
    128i .. 128i+127, lanes past numel zero -- the layout every activation on
    the chip uses, so y is the next kernel's input. b is the same: nothing is
    broadcast (`broadcast` = none, `inner` = 0), so its row i holds the
    elements a's row i is combined with.

    Dataflow, per row: an operand that lives in XMEM costs a LOAD and a word
    has one LOAD slot, so an elementwise case is two words per row and each of
    them runs the multiplier: word A multiplies the b row resident in R1 by the
    CR constant 1.0 and initialises the accumulator with it, word B multiplies
    the a row resident in R0 by 1.0, accumulates it and stores the row; each
    word loads the row the *next* word multiplies (MULT reads R0/R1/R_CYCLIC at
    cycle start, LOAD reads LRs after the same word's writes). A row of `mul`
    is one product, a * b, so its second word carries only the b load: two
    words per row for every op, the floor one LOAD slot and one MULT slot per
    word allows a two-operand elementwise op.

    Timing contract: the Control stage (LR writes, branch) reads LRs at cycle
    start; LOAD/MULT/ACC/AAQ read them after the same word's LR writes. Hence
    the counters: LR2 and LR5 are the b and a row pointers, each written in the
    word whose LOAD uses the new value, and LR3 is the row being stored,
    advanced in the word that does NOT store with it. A body branches on the
    pointer it is about to move, read at cycle start, so the bound is the last
    index that still loops. Two LR sub-slots never write one register in one
    word (fault F-3), which is why a counter that is set and stepped needs two
    words.

    The last row of a call is usually short: numel - 128*(rows-1) lanes. Its
    store names that many lanes, so the row's scale comes from real data and
    the lanes past numel are written 0 for whatever kernel reads y next. The
    loop therefore runs the full rows only and the last row is emitted
    straight-line with its own DS half; the row before it is emitted
    straight-line too, which is what keeps the pipeline's one-row-ahead loads
    inside the regions (nothing ever loads row `rows`).

    LR: LR0 0; LR2 the b row pointer; LR3 the y row being stored; LR4 the row
    loop's bound; LR5 the a row pointer; LR11 128 (R1's element offset in Ra).
    The program sets every LR it reads and loads its own mask row, so it runs
    after another kernel as well as from reset.
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
    INC LR3 1{% if loads %} ;
    INC LR2 1 ;
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
    INC LR2 1 ; INC LR3 1 ;
    LD.MULT R1 LR2 {{ cr.b }}{% if branch %} ;
    BLT.S LR2 LR4 row_loop ;;{% else %} ;;{% endif %}{% else %} ;;{% endif %}
{%- endmacro %}
{#- The two-word body stores with the row index its first word advanced (LR3
    starts one behind); the one-product body stores with the index its previous
    word advanced, so LR3 starts at 0 there. -#}
{% set body = bodymul if op == "mul" else body2 %}

    SET LR0 CR0 ; SET LR11 {{ cr.slot1 }} ;;              {#- 0; R1's element offset in Ra -#}
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
    LD.MULT R1 LR2 {{ cr.b }} ;;                          {#- prime: b[0] -> R1 -#}
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
