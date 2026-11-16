    SET LR0 CR0 ;;
    SET LR2 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
{% for i in range(5) %}
    SET LR1 CR0 ;;
    INC LR1 {{ i }} ;;
    LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}
row_loop:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    SET LR12 LR11 ;;
    INC LR12 1 ;;
    BGE.S LR12 {{ cr.memrows }} skip_next ;;
    LD.MULT R1 LR12 {{ cr.in0 }} ;;
skip_next:
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR10 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.MAX.FIRST LR0 CR15.L ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    BGE.S LR12 {{ cr.memrows }} skip_reload ;;
    LD.MULT R1 LR12 {{ cr.in0 }} ;;
skip_reload:
    MULT.VE LR10 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE generic CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    SET LR1 CR0 ;;
    INC LR1 7 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in [4,5] %}
    SET LR1 CR0 ;;
    INC LR1 {{ j }} ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR1 CR0 ;;
    INC LR1 4 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR9 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR9 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.results }} LR2 ;;
    ADD LR10 LR10 {{ cr.n }} ;;
    BLT.S LR10 {{ cr.width }} next_row ;;
    SUB LR10 LR10 {{ cr.width }} ;;
    INC LR11 1 ;;
next_row:
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row_loop ;;
    SET LR2 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
    SET LR13 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
pack_tile:
    SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    SET LR12 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
pack_element:
    LD.MULT R0 LR2 {{ cr.results }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf }}.L ; ACC.RESHAPE LRD6 LRD4 7 ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.n }} same_row ;;
    SET LR10 CR0 ;;
    INC LR2 1 ;;
same_row:
    INC LR13 1 ;;
    INC LR12 1 ;;
    BGE.S LR13 {{ cr.total }} pack_end ;;
    ADDBI LRD4 1 ;;
    BLT.S LR12 {{ cr.width }} pack_element ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
    BLT.S LR13 {{ cr.total }} pack_tile ;;
pack_end:
    BLT.S LR12 {{ cr.width }} partial ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf }}.L {{ cr.out0 }} LR11 ;;
    HALT ;;
partial:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR11 ;;
    HALT ;;
