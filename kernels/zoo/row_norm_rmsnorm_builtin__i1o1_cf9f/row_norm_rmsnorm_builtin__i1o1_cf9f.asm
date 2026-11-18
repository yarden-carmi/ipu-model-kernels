    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scale }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR0 {{ cr.scale_lo }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    LD.MULT R0 LR0 {{ cr.bias }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_bias }}.L ; ACC.ADD ;;
    LD.MULT R0 LR0 {{ cr.bias_lo }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_bias_lo }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.count }} row ;;
    HALT ;;
