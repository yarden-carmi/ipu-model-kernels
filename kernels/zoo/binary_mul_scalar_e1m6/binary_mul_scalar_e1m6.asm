    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    LD.MULT R0 LR0 {{ cr.operand }} ;;
loop:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    BLT.S LR1 {{ cr.last }} full ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    HALT ;;
full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;
