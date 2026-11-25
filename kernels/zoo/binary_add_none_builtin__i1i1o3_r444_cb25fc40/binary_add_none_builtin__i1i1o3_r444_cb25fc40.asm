    SET LR0 CR0 ; SET LR5 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
group:
    SET LR6 LR9 ; SET LR1 CR0 ; SET LR8 CR0 ;;
channel:
    SET LR4 LR6 ; SET LR3 CR0 ;;
width:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.single }}.L ; LD.MULT R0 LR4 {{ cr.in1 }} ;;
    MULT.EE LR1 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.single }}.L ; ADD LR4 LR4 {{ cr.chunks }} ;;
    INC LR3 1 ;;
    BNE LR3 {{ cr.out0_d3 }} width ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.width_mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR8 1 ; INC.MODP2 LR1 {{ cr.one }} 7 ;;
    BEQ LR8 {{ cr.out0_d1 }} next_group ;;
    BNE LR1 CR0 channel ;;
    INC LR6 1 ; BEQ CR0 CR0 channel ;;
next_group:
    ADD LR9 LR9 {{ cr.group_stride }} ; INC LR10 1 ;;
    BNE LR10 {{ cr.groups }} group ;;
    HALT ;;
