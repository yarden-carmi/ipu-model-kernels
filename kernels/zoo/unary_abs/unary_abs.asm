{#- unary_abs.asm -- y = |x| elementwise over numel elements in 128-lane rows,
    ONE parameterised program for every numel: the rows are a dynamic loop whose
    bound is a CR, so a whole call is one launch and the host tiles nothing but
    numel.

    x and y are the plain activation layout (row r holds lanes 128r .. 128r+127,
    lanes past numel zero), so this kernel reads the rows the previous kernel
    wrote and writes the rows the next one reads, with no repack between them.
    |0| = 0, so a zero-padded input row keeps a zero-padded output row.

    Hardware-clean NX8: formats = ["dynamic"], every store is an ACTIVATE.QUANTIZE
    (identity) and no emulator-only instruction appears.

    The datapath has no absolute value, but the accumulator has MAX and a negate:
    ACC.SUB.FIRST of x*1.0 puts -x in R_ACC, and ACC.MAX of the same product
    maxes it with +x:

        |x| = max(-x, x)

    two words per row, both running the multiplier, and no intermediate row: the
    only rounding in the whole kernel is the output store, whose row quantization
    the golden applies to the same row, so the result is exact on the row's grid.

    Timing contract (docs/content/explanation/timing-model.md): LOAD reads the
    LRs *after* the same word's LR writes, so the x walk is INC'd in its own load
    word and names the next row; MULT reads R_CYCLIC as the word began, so the
    load is one word ahead of the multiply that consumes it; ACC takes this
    word's MULT_RES and ACTIVATE.QUANTIZE this word's R_ACC, so the two
    multiplies, the max and the store are the whole body; the LR sub-slots and
    the branch read cycle-start values. LR0 is zeroed before anything reads it
    (slot 0, the mask shift and the cyclic window's base) and R_MASK is loaded
    from its own all-ones row, so the program runs after another kernel as well
    as from reset.

    The last row of a call is usually short (numel - 128*(rows-1) lanes) and is
    emitted straight-line with the DS half CR15.H: the store names exactly the
    live lanes, so the row's scale comes from real data and the lanes past numel
    are written 0 for whatever kernel reads y next. The loop therefore runs the
    full rows only, and its last iteration's one-row-ahead load still names row
    rows-1, inside the region.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{% set M = "MULT.RC.VE LR0 CR1 0 LR0 " %}
    SET LR0 CR0 ; LD.MASK LR0 {{ cr.maskr }} ;;           {#- 0: slot 0, the mask shift, the cyclic base -#}
    SET LR2 {{ cr.bound }} ; SET LR6 CR0 ;;               {#- the loop's bound; the x row walk -#}
    SUB LR7 LR0 CR1 ;;                                    {#- the store walk, one behind -#}
    LD.MULT.CYCLIC LR0 {{ cr.x }} LR0 ;;                  {#- prime: x[0] -> R_CYCLIC[0..127] -#}
{% if rows >= 2 %}
row_loop:
    {{ M }}{{ dsf }} {{ qfl }} ;                          {#- x[row] * 1.0 -#}
    ACC.SUB.FIRST ;                                       {#- R_ACC = -x[row] -#}
    INC LR7 1 ;;
    {{ M }}{{ dsf }} {{ qfl }} ;                          {#- the same product again -#}
    ACC.MAX ;                                             {#- R_ACC = max(-x, x) = |x| -#}
    ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR7 ;
    INC LR6 1 ;
    LD.MULT.CYCLIC LR6 {{ cr.x }} LR0 ;                   {#- x[row + 1] for the next word -#}
    DEC LR2 1 ;
    BLT.S CR0 LR2 row_loop ;;
{% endif %}
last:
    {{ M }}{{ dsl }} {{ qfl }} ;
    ACC.SUB.FIRST ;
    INC LR7 1 ;;
    {{ M }}{{ dsl }} {{ qfl }} ;
    ACC.MAX ;
    ACTIVATE.QUANTIZE identity {{ dsl }} {{ qfl }} {{ cr.y }} LR7 ;;
end:
    HALT ;;
