    SET LR0 CR0 ;;
    LD.MULT R0 LR0 {{ cr.operand }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR0 ;;
    HALT ;;
