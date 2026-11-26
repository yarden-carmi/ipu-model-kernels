    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
    SET LR13 CR0 ;;
batch:
    SET LR12 CR0 ;;
width:
    SET LR6 CR0 ;;
channel:
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR8 CR0 ;;
    ADD LR7 LR10 LR12 ;;
height:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ;;
    ADD LR7 LR7 {{ cr.in0_d3 }} ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.in0_d2 }} height ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.in0_d1 }} channel ;;
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.in0_d3 }} width ;;
    ADD LR10 LR10 {{ cr.batchstride }} ;;
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.in0_d0 }} batch ;;
    HALT ;;
