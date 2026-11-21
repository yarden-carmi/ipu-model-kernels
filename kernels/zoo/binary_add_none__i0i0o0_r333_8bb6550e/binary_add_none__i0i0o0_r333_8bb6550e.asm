// The view visits storage offsets sequentially with a fastest, then b,
// then c. Physical input rows hold consecutive offsets within each
// storage plane; wrapping the row advances the storage lane.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    SET LR7 CR0 ; SET LR9 CR0 ;;
column:
    SET LR10 LR9 ; SET LR11 {{ cr.out0_d1 }} ;;
row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 {{ cr.out0_d0 }} ;;
lane:
    LD.MULT R0 LR7 {{ cr.in0 }} ; DEC LR8 1 ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR7 1 ;;
    BNE LR7 {{ cr.in0_rows }} next_lane ;;
    SET LR7 CR0 ; INC LR6 1 ;;
next_lane:
    ADDBI LRD2 1 ; BNE LR8 CR0 lane ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ; DEC LR11 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    ADD LR10 LR10 {{ cr.out0_d2 }} ; BNE LR11 CR0 row ;;
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d2 }} column ;;
    HALT ;;
