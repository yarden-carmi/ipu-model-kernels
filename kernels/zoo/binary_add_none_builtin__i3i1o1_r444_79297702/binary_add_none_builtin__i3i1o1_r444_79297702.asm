    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ;;
batch:
    ADD LR10 LR9 {{ cr.channel_stride }} ; SET LR5 LR9 ;;
pair:
    SET LR4 CR0 ;;
pixel:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 LR5 ;;
    SET LR7 CR0 ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR7 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.mask }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ cr.channel_stride }} ;;
    ADDBI LRD2 1 ; BNE LR7 {{ cr.out0_d1 }} channel ;;
    LD.MULT R0 LR8 {{ cr.in1 }} ; INC LR4 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; BNE LR4 {{ cr.pair_lanes }} pixel ;;
    INC LR5 1 ;;
    BNE LR5 LR10 pair ;;
    ADD LR9 LR9 {{ cr.batch_stride }} ; BNE LR8 {{ cr.pixels }} batch ;;
    HALT ;;
