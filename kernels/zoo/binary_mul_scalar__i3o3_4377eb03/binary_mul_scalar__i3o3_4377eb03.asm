    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
group:
    SET LR3 CR1 ;;
chunk:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ cr.fp_scale if format == 'fp32' else cr.scale }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    BEQ LR3 {{ cr.chunks }} tail ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    INC LR3 1 ;;
    BNE LR3 CR0 chunk ;;
tail:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.groups }} group ;;
    HALT ;;
