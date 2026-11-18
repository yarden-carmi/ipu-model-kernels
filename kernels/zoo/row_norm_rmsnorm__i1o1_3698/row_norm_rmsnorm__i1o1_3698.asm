    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    SET LR2 CR0 ;;
group:
    SET LR1 CR0 ;;
row:
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.scale }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR1 {{ cr.scale_lo }} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    LD.MULT R0 LR1 {{ cr.bias }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_bias }}.L ; ACC.ADD ;;
    LD.MULT R0 LR1 {{ cr.bias_lo }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_bias_lo }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    INC LR1 1 ;;
    BLT.S LR1 LR7 row ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.spatial }} group ;;
    HALT ;;
