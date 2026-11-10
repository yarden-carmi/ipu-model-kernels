{#- layout_concat.asm -- y = cat((a, b), dim=0) (kind = concat), or y = a
    (kind = copy), one parameterised program for every (kind, numel).

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes). a, b and y are numel/128 rows each, row i holding elements 128i ..
    128i+127 -- the layout every activation on the chip uses. A concat's two
    operands hold rows/2 rows of real data at their base (exactly what a
    producer that wrote a numel/2-element tensor left there), and the kernel
    puts them end to end in y: y's rows 0 .. rows/2-1 are a's, y's rows
    rows/2 .. rows-1 are b's. A copy writes y's rows from a's rows and reads
    nothing from b. Neither pass looks inside a row, so the kernel reads the
    rows the previous kernel wrote and leaves rows the next one reads.

    Dataflow, per row: the only way into R_ACC is a multiply result, and a word
    has one LOAD, one MULT, one ACC and one AAQ slot, so a copied row is exactly
    one word: it multiplies the row resident in R0 by the CR constant 1.0
    (MULT.VE, an exact product), writes it to the accumulator (ACC.ADD.FIRST)
    and stores it (ACTIVATE.QUANTIZE identity), while the same word loads the
    row the *next* word multiplies and steps the three counters. LOAD reads LRs
    after the same word's LR writes and MULT/AAQ read the registers as the word
    began, hence: INC LR1 1 ; LD.MULT R0 LR1 base loads row i+1 while MULT
    multiplies row i, and ADD LR2 LR1 off gives the store this row's index (LR1
    read at cycle start, before this word's INC). BLT.S reads LR3, the counter
    kept one ahead (set to 1 before the loop), before this word's INC. One word
    per row, the multiplier issuing in every word of both loops (its lane
    occupancy is 100%; the reported MAC utilization is 0% because every
    multiply here is the identity by 1.0, the only way a row reaches R_ACC):
    20480 elements is 173 cycles, 196608 is 1549, 698880 is 5473.

    The last row of a pass is peeled straight-line without its prefetch, so no
    load ever names a row past a region (a pass of one row is only the peeled
    row); a pass of no rows -- a copy's second -- is skipped by its guard word,
    which is what lets the same program serve both kinds.

    LR: LR0 0 (the MULT's element index and mask shift); LR1 the source row
    pointer; LR2 the y row being stored; LR3 the row counter, one ahead. The
    program sets every LR it reads and loads its own mask row, so it runs after
    another kernel as well as from reset; R_ACC is written, never accumulated,
    by ACC.ADD.FIRST, so what a previous kernel left there cannot matter.
-#}
{% set dsf = cr.ds ~ ".L" %}
{% set qfl = cr.qf ~ ".L" %}
{#- Each pass: its source base, the CR of its row count, of its loop's trips,
    and of the y row its source row lands on (the source row + that CR). -#}
{% if kind == "copy" %}
{% set passes = [(cr.a, cr.rows, cr.loop_copy, "CR0", "pa"), (cr.b, cr.zero, cr.zero, cr.half, "pb")] %}
{% else %}
{% set passes = [(cr.a, cr.half, cr.loop_a, "CR0", "pa"), (cr.b, cr.half, cr.loop_a, cr.half, "pb")] %}
{% endif %}
{% macro copy_pass(base, nrows, nloop, off, tag) -%}
    SET LR1 CR0 ; SET LR3 CR0 ;;                                {#- the source pointer, the counter -#}
    BEQ LR3 {{ nrows }} {{ tag }}_done ;;                        {#- the pass is empty: skip it -#}
    LD.MULT R0 LR1 {{ base }} ;;                                 {#- prime: row 0 -> R0 -#}
    BEQ LR3 {{ nloop }} {{ tag }}_tail ;;                        {#- one row: only the peeled word -#}
    INC LR3 1 ;;                                                 {#- the counter, one ahead -#}
{{ tag }}_loop:
    INC LR1 1 ; ADD LR2 LR1 {{ off }} ; INC LR3 1 ;
    LD.MULT R0 LR1 {{ base }} ;
    MULT.VE LR0 CR1 0 LR0 {{ dsf }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR2 ;
    BLT.S LR3 {{ nloop }} {{ tag }}_loop ;;
{{ tag }}_tail:
    ADD LR2 LR1 {{ off }} ;
    MULT.VE LR0 CR1 0 LR0 {{ dsf }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR2 ;;
{{ tag }}_done:
{%- endmacro %}

    SET LR0 CR0 ;;                                               {#- 0: the element index, the mask shift -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                                {#- every lane of every multiply active -#}
{% for base, nrows, nloop, off, tag in passes %}
{{ copy_pass(base, nrows, nloop, off, tag) }}
{% endfor %}
    HALT ;;
