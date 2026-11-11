{#- binary_mul_scalar.asm -- y = a (op) b[0] elementwise, one parameterised
    program for every (op, numel) of the kernel's domain.

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are ceil(numel/128) rows each, row i holding elements
    128i .. 128i+127, lanes past numel zero -- the layout every activation on
    the chip uses, so y is the next kernel's input. b is one row: the scalar in
    lane 0, the rest zero.

    Dataflow, per row: an operand that lives in XMEM costs a LOAD and a word
    has one LOAD slot, and a row of y needs one multiply per operand (the only
    way into R_ACC is MULT_RES). The scalar is loaded ONCE into R1 and selected
    from it by LR (an LR src of 128 names R1[0]), so a row costs no load of b:
    a row of `mul` is ONE word -- it loads the next a row into R_CYCLIC,
    multiplies the resident one by the scalar, initialises the accumulator with
    the product and stores it. add/sub/max need the scalar as a second product,
    broadcast: word A multiplies the resident a row by the CR constant 1.0 and
    initialises the accumulator, word B broadcasts b (MULT.EE of R1[0] by 1.0),
    accumulates it and stores the row; word A carries the load of the row the
    *next* word A multiplies (MULT reads R_CYCLIC at cycle start, LOAD reads
    LRs after the same word's writes), so nothing waits on a load.

    Timing contract: the Control stage (LR writes, branch) reads LRs at cycle
    start; LOAD/MULT/ACC/AAQ read them after the same word's LR writes. Hence
    the counters: LR1 is the a row pointer, INC'd in the word whose LOAD uses
    the new value; LR2 is the row being stored, ADDed from LR1 *before* LR1's
    INC is visible; LR3 is one ahead of the words done, so the branch at the
    end of the loop body (mul) or of every second word (add/sub/max) reads the
    index of the row the loop is about to leave for.

    The last row of a call is usually short: numel - 128*(rows-1) lanes. Its
    store names that many lanes, so the row's scale comes from real data and
    the lanes past numel are written 0 for whatever kernel reads y next. The
    loop therefore runs the full rows only and the last row is emitted
    straight-line with its own DS half: the loop's last load brings exactly
    row rows-1 into R_CYCLIC, nothing ever loads row `rows`.

    LR: LR0 0 (R_CYCLIC element index / mask shift); LR1 the a row pointer;
    LR2 the y row being stored; LR3 the branch counter; LR5 128 (the scalar's
    element index in Ra: R1[0]). The program sets every LR it reads and loads
    its own mask row, so it runs after another kernel as well as from reset.
-#}
{% set rows = (numel + 127) // 128 %}
{% set tail = numel - 128 * (rows - 1) %}
{% set hastrail = tail != 128 %}
{% set dsf = cr.ds ~ ".L" %}
{% set dsl = cr.ds ~ (".H" if hastrail else ".L") %}
{% set qfl = cr.qf ~ ".L" %}
{% set A1 = {"add": "ACC.ADD.FIRST", "sub": "ACC.ADD.FIRST", "max": "ACC.MAX.FIRST"}[op] %}
{% set A2 = {"add": "ACC.ADD", "sub": "ACC.SUB", "max": "ACC.MAX"}[op] %}

    SET LR0 CR0 ; SET LR1 CR0 ;;                          {#- 0; the a row pointer -#}
    SET LR2 CR0 ; SET LR3 CR1 ;;                          {#- the store row; the branch counter -#}
    SET LR5 {{ cr.slot1 }} ;;                             {#- the scalar is R1[0] -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
    LD.MULT R1 LR1 {{ cr.b }} ;;                          {#- the scalar -> R1 -#}
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;;                  {#- prime: a[0] -> R_CYCLIC[0..127] -#}
{% if rows >= 2 %}
{% if op == "mul" %}
row_loop:
    INC LR1 1 ; ADD LR2 LR1 CR0 ; INC LR3 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;
    MULT.RC.VE LR0 LR5 0 LR0 {{ dsf }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR2 ;
    BLT.S LR3 {{ cr.bound }} row_loop ;;
{% else %}
row_loop:
    INC LR1 1 ; ADD LR2 LR1 CR0 ; INC LR3 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR0 ;
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsf }} {{ qfl }} ;
    {{ A1 }} ;;
    MULT.EE LR5 CR1 0 LR0 {{ dsf }} {{ qfl }} ;
    {{ A2 }} ;
    ACTIVATE.QUANTIZE identity {{ dsf }} {{ qfl }} {{ cr.y }} LR2 ;
    BLT.S LR3 {{ cr.rows }} row_loop ;;
{% endif %}
{% endif %}
    SET LR2 {{ cr.bound }} ;;                             {#- the last row's index -#}
{% if op == "mul" %}
    MULT.RC.VE LR0 LR5 0 LR0 {{ dsl }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsl }} {{ qfl }} {{ cr.y }} LR2 ;;
{% else %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ dsl }} {{ qfl }} ;
    {{ A1 }} ;;
    MULT.EE LR5 CR1 0 LR0 {{ dsl }} {{ qfl }} ;
    {{ A2 }} ;
    ACTIVATE.QUANTIZE identity {{ dsl }} {{ qfl }} {{ cr.y }} LR2 ;;
{% endif %}
end:
    HALT ;;
