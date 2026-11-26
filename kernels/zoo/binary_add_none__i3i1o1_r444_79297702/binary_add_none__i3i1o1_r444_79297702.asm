    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
pixel:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 LR5 ;;
    SET LR7 CR0 ;;
channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR7 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.ds_channels }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ cr.channel_stride }} ;;
    ADDBI LRD2 1 ; BNE LR7 {{ cr.out0_d1 }} channel ;;
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_channels }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_channels }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR4 1 ;;
    BEQ LR8 {{ cr.pixels }} done ;;
    BNE LR4 {{ cr.spatial_lanes }} pixel ;;
    SET LR4 CR0 ; INC LR5 1 ; INC LR9 1 ;;
    BNE LR9 {{ cr.channel_stride }} pixel ;;
    SET LR9 CR0 ; ADD LR5 LR5 {{ cr.batch_skip }} ; B pixel ;;
done:
    HALT ;;
