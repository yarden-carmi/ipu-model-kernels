    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 CR0 ;;
height:
    SET LR4 CR0 ;;
channel:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 LR5 ;;
    SET LR7 CR0 ; LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR4 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR7 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR6 1 ;;
    ADDBI LRD2 1 ; BNE LR7 {{ cr.in0_d3 }} gather ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR4 1 ;;
    BNE LR4 {{ cr.in0_d1 }} channel ;;
    ADD LR5 LR5 {{ cr.in0_d3 }} ; INC LR10 1 ;;
    BNE LR10 {{ cr.heights }} height ;;
    HALT ;;
