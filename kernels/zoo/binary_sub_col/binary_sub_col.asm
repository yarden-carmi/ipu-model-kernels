{#- binary_sub_col.asm -- y = a (op) b, broadcast = col, one parameterised
    program for every (op, numel, inner) of the kernel's domain.

    Layout (kernel.toml's [abi]; every operand is a ROW number, one row = 128
    lanes): a and y are [inner, numel / inner] -- an entity (a row of a) is
    one memory row, its numel / inner features in lanes 0..rowlen-1, lanes
    past that zero -- the layout every activation on the chip uses when an
    entity holds at most 128 features, so y is the next kernel's input. b
    holds `inner` values, one per row of a, in the lanes of one row.

    Dataflow, per row r: y[r] = a[r] (op) b[r], so the row needs TWO products
    (the only way into R_ACC is MULT_RES): word A multiplies the a row
    resident in R_CYCLIC slot 128 by the CR constant 1.0 and initialises the
    accumulator with it, word B broadcasts b[r] (MULT.RC.VE of the resident
    ones row in slot 0, the scalar element 128 + r of Ra = R1 selected by LR5)
    and accumulates it (ADD for add, SUB for sub, MAX for max) and stores the
    row. `mul` is ONE product -- the a row itself times b[r] -- so its whole
    row is one word. Word A carries the load of the row the next word A
    multiplies (MULT reads R_CYCLIC at cycle start, LOAD reads LRs after the
    same word's writes), so nothing waits on a load. The ones row and b are
    loaded once in the prologue.

    Timing contract: the Control stage (LR writes, branch) reads LRs at cycle
    start; LOAD/MULT/ACC/AAQ read them after the same word's LR writes. Hence
    the counters: LR1 is the a row pointer, INC'd in the word whose LOAD uses
    the new value; LR2 (the row being stored) is ADDed from LR1 - 1 in word B
    or from LR1 in the one-word `mul` body, both read at cycle start; the
    branch reads LR1 before its same-word INC, so the loop runs rows - 1
    times (it never loads row `rows`) and the last row is emitted straight-
    line with the same DS half -- every row of a holds exactly `inner` lanes,
    so there is no short last row. MULT.RC.VE's scalar src reads its LR
    forwarded, so word B's INC LR5 1 selects b[r] and leaves 128 + r + 1.

    LR: LR0 0 (R_CYCLIC element index / mask shift); LR1 the a row pointer;
    LR2 the y row being stored; LR5 the b element index in Ra minus one
    (starts 127); LR7 the a rows' R_CYCLIC slot (128). The program sets every
    LR it reads and loads its own mask row, so it runs after another kernel
    as well as from reset.
-#}
{% set rows = inner %}  {#- the entities: b holds one value per row of a -#}
{% set dsx = cr.ds ~ ".L" %}
{% set qfl = cr.qf ~ ".L" %}
{% set A1 = {"add": "ACC.ADD.FIRST", "sub": "ACC.ADD.FIRST", "max": "ACC.MAX.FIRST"}[op] %}
{% set A2 = {"add": "ACC.ADD", "sub": "ACC.SUB", "max": "ACC.MAX"}[op] %}

    SET LR0 CR0 ; SET LR1 CR0 ;;                          {#- 0; the a row pointer -#}
    SET LR5 {{ cr.slot1m1 }} ; SET LR7 {{ cr.slot128 }} ;; {#- b's Ra index - 1; a's cyclic slot -#}
    LD.MASK LR0 {{ cr.maskr }} ;;                         {#- every lane of every multiply active -#}
    LD.MULT R1 LR1 {{ cr.b }} ;;                          {#- b's row -> R1, selected per row by LR5 -#}
    LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;               {#- the ones row -> R_CYCLIC slot 0 -#}
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;;                  {#- prime: a[0] -> R_CYCLIC slot 128 -#}
{% if rows >= 2 %}
{% if op == "mul" %}
row_loop:
    ADD LR2 LR1 CR0 ; INC LR1 1 ; INC LR5 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;
    MULT.RC.VE LR7 LR5 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;
    BLT.S LR1 {{ cr.bound }} row_loop ;;
{% else %}
row_loop:
    INC LR1 1 ;
    LD.MULT.CYCLIC LR1 {{ cr.a }} LR7 ;
    MULT.RC.VE LR7 CR1 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A1 }} ;;
    SUB LR2 LR1 CR1 ; INC LR5 1 ;
    MULT.RC.VE LR0 LR5 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A2 }} ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;
    BLT.S LR1 {{ cr.bound }} row_loop ;;
{% endif %}
{% endif %}
{% if op == "mul" %}
{% if rows == 1 %}
    SET LR2 CR0 ; INC LR5 1 ;;
{% else %}
    ADD LR2 LR1 CR0 ; INC LR5 1 ;;
{% endif %}
    MULT.RC.VE LR7 LR5 0 LR0 {{ dsx }} {{ qfl }} ;
    ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;;
{% else %}
    MULT.RC.VE LR7 CR1 0 LR0 {{ dsx }} {{ qfl }} ;         {#- the last row's a product -#}
    {{ A1 }} ;;
{% if rows == 1 %}
    SET LR2 CR0 ; INC LR5 1 ;;
{% else %}
    SUB LR2 LR1 CR0 ; INC LR5 1 ;;
{% endif %}
    MULT.RC.VE LR0 LR5 0 LR0 {{ dsx }} {{ qfl }} ;
    {{ A2 }} ;
    ACTIVATE.QUANTIZE identity {{ dsx }} {{ qfl }} {{ cr.y }} LR2 ;;
{% endif %}
end:
    HALT ;;
