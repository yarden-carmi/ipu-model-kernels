    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
loop:
    LD.MULT R0 LR2 {{ cr.operand }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.period }} next ;;
    SET LR2 CR0 ;;
next:
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;
