    SET LR0 CR0 ;;
    LD.MULT R0 LR0 {{ cr.one }} ;;
    SET LR14 CR0 ;;
route:
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.RESHAPE LRD10 LRD12 7 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.routing }} LR14 ;;
    INC LR14 1 ;;
    ADDBI LRD12 1 ;;
    BLT.S LR14 {{ cr.reg_offset }} route ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
block:
    SET LR3 CR0 ;;
height:
    SET LR4 CR0 ;;
width:
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ;;
    ADD LR6 LR2 LR3 ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    LD.MULT R1 LR6 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.routing }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ADD LR7 LR4 {{ cr.reg_offset }} ;;
    MULT.RC.VE LR0 LR7 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR5 1 ;;
    ADD LR6 LR6 {{ cr.height }} ;;
    BLT.S LR5 {{ cr.lanes }} channel ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.width }} width ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.height }} height ;;
    ADD LR2 LR2 {{ cr.block_rows }} ;;
    BLT.S LR2 {{ cr.rows }} block ;;
    HALT ;;
