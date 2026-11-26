    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
batch:
    SET LR4 {{ cr.out0_d1 }} ; SET LR5 LR2 ;;
channel:
    SET LR6 {{ cr.out0_d2 }} ; SET LR7 LR5 ;;
packed_row:
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR8 CR0 ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ; SET LR9 CR0 ;;
    INC LR9 128 ; INC LR1 1 ;;
slice:
    // Each pair of packed loads serves all width slices in this row.
    MULT.VE LR8 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR9 CR1 0 LR0 {{ cr.width_ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    DEC LR6 1 ; ADD LR7 LR7 {{ cr.out0_d1 }} ;;
    BEQ LR6 CR0 next_channel ; ADD LR8 LR8 {{ cr.out0_d3 }} ; ADD LR9 LR9 {{ cr.out0_d3 }} ;;
    BLT.S LR8 {{ cr.packed_end }} slice ;;
    B packed_row ;;
next_channel:
    DEC LR4 1 ; INC LR5 1 ;;
    BNE LR4 CR0 channel ;;
    INC LR3 1 ; ADD LR2 LR2 {{ cr.batch_stride }} ;;
    BLT.S LR3 LR15 batch ;;
    HALT ;;
