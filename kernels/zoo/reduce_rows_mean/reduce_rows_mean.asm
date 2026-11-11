{#- reduce_rows_mean.asm -- y[r] = reduce(x[r, 0:n]) for each row of a
    (rows, n) matrix: sum, mean or max. One parameterised program for every
    (kind, rows, n): the row loop is dynamic and the row's 128-lane chunks are
    rendered per call, so the shape reaches the program only through CRs and
    one launch takes a whole call.

    Layout: x is the chip's activation layout, entity r holding its n values in
    ceil(n / 128) consecutive rows (lanes past n zero); y holds one value per
    entity, in lane 0 of its own row -- what AGG writes (R_ACC slot 0) and what
    the store names with a DS of one active lane.

    Dataflow, one word per x row: MULT of the row resident in R_CYCLIC slot 0
    (the previous word's load) by 1.0 (sum, max) or by the resident 1/n row
    (mean, so the reduction lands on the mean directly, with no quantized sum
    in front of it); AGG.SUM / AGG.MAX into R_ACC slot 0, seeded by the .FIRST
    form at the row's first chunk; and, at the row's last chunk, the
    ACTIVATE.QUANTIZE identity store of that lane. The next row's load rides in
    the word that multiplies the current one (MULT reads R_CYCLIC at cycle
    start, LOAD reads LRs after the same word's LR writes), so a row costs one
    word per chunk and nothing else.

    Timing contract: the LR sub-slots and the branch read cycle-start values,
    so the store's row is named by ADD LR2 LR4 CR0 (the entity counter, read
    before its INC) and the loop's branch tests the row the word multiplies
    (the x walk, read before its INC) against CR12 = (rows - 1) * chunks - 1:
    the loop runs the first rows - 1 entities and the last one is emitted
    straight-line, which is also what keeps the one-row-ahead prefetch inside
    x's region (a bound one row too high would store the tail's last chunk past
    y's rows). Two LR sub-slots never write one register (fault F-3), which is
    why the store index needs its own LR.

    A sum or max row is multiplied by the exact CR constant 1.0 to bring it
    into MULT_RES (the only way into R_ACC); the emulator's MAC statistic
    writes such a declared identity off, so its report says 0% for those kinds
    even though every word of the row loop runs the reduction stage. A mean
    multiplies by the resident 1/n row, a real multiply, and reports the lanes
    its DS names (n of 128).

    LR: LR0 0 (the cyclic slot, AGG's destination lane, the mask shift); LR1 the
    x row walk; LR2 the y row this word stores; LR4 the entity counter. The
    program sets every LR it reads and loads its own mask row, so it runs after
    another kernel as well as from reset.
-#}
{% set C = (n + 127) // 128 %}
{% set tail = n - 128 * (C - 1) %}
{% set hastail = tail != 128 %}
{% set qfl = cr.qf ~ ".L" %}
{% set dsl = cr.ds ~ ".L" %}
{% set dsh = cr.ds ~ (".H" if hastail else ".L") %}
{% set A0 = "AGG.MAX.FIRST" if kind == "max" else "AGG.SUM.FIRST" %}
{% set A1 = "AGG.MAX" if kind == "max" else "AGG.SUM" %}
{% macro word(c, loads, counters, branch) -%}
{% set dsx = dsl if c < C - 1 else dsh %}
{% if kind == "mean" %}MULT.RC.VV LR0 R1 0 LR0 {{ dsx }} {{ qfl }}{% else %}MULT.RC.VE LR0 CR1 0 LR0 {{ dsx }} {{ qfl }}{% endif %} ;
{{ A0 if c == 0 else A1 }} LR0 {{ dsx }} ;
{%- if c == C - 1 %} ADD LR2 LR4 CR0 ;{% if counters %} INC LR4 1 ;{% endif %}
ACTIVATE.QUANTIZE identity {{ cr.ds1 }}.L {{ qfl }} {{ cr.y }} LR2 ;
{%- endif %}
{%- if loads %} INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;{% endif %}
{%- if c == C - 1 and branch %} BLT.S LR1 {{ cr.bound }} row_loop ;{% endif %} ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    LD.MASK LR0 {{ cr.maskr }} ;;
{% if kind == "mean" %}
    LD.MULT R1 LR0 {{ cr.invn }} ;;                        {#- the resident 1/n row -#}
{% endif %}
    LD.MULT.CYCLIC LR1 {{ cr.x }} LR0 ;;                   {#- prime: x row 0 -> R_CYCLIC slot 0 -#}
{% if rows >= 2 %}

row_loop:
{% for c in range(C) %}
{{ word(c, true, true, c == C - 1) }}
{% endfor %}
{% endif %}
{% for c in range(C) %}
{{ word(c, c < C - 1, false, false) }}
{% endfor %}

end:
    HALT ;;
