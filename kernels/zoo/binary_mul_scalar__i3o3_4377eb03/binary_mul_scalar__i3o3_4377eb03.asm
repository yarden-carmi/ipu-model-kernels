    SET LR0 CR0 ;;
    LD.MULT R0 LR0 {{ cr.scale }} ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
group:
    SET LR3 CR1 ;;
chunk:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
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
