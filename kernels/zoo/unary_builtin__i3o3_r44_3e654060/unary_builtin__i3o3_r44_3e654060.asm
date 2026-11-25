    {# LR2 is the sequential output row. LR3 is the input batch base. #}
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
batch:
    SET LR4 LR3 ;;
    SET LR5 CR0 ;;
channel:
    SET LR6 LR4 ;;
    ADD LR7 LR4 {{ cr.tile_rows }} ;;
row:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.input_active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    INC LR6 1 ;;
    BLT.S LR6 LR7 row ;;
    ADD LR4 LR4 {{ cr.channel_stride }} ;;
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.in0_d1 }} channel ;;
    ADD LR3 LR3 {{ cr.tile_rows }} ; BLT.S LR2 {{ cr.output_rows }} batch ;;
    HALT ;;
