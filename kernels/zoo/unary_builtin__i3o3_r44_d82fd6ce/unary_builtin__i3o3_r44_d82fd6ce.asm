    SET LR1 CR0 ; SET LR2 CR0 ;;
channel:
    SET LR3 CR0 ; SET LR8 LR2 ;;
batch:
    SET LR4 CR0 ; SET LR7 LR8 ;;
group:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
segment:
    MULT.RC.VE LR6 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    ADD LR7 LR7 {{ cr.in0_d1 }} ; ADD LR6 LR6 {{ cr.in0_d3 }} ; INC LR5 1 ; BLT.S LR5 {{ cr.pack_last }} segment ;;
    INC LR1 1 ; INC LR4 1 ; BLT.S LR4 {{ cr.group_last }} group ;;
    INC LR3 1 ; ADD LR8 LR8 {{ cr.batch_stride }} ; BLT.S LR3 {{ cr.batch_last }} batch ;;
    INC LR2 1 ; BLT.S LR2 {{ cr.channel_last }} channel ;;
    HALT ;;
