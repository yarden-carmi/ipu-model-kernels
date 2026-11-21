// Output rows follow the view's storage order. Walk in0's logical
// storage offsets in sequence, translating them to its physical rows.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 {{ cr.out0_d0 }} ;;
lane:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 7 ; INC LR5 1 ;;
    ADD LR7 LR7 {{ cr.in0_d1 }} ; BLT.S LR5 {{ cr.in0_d2 }} next_lane ;;
    INC LR4 1 ; SET LR5 CR0 ;;
    BLT.S LR4 {{ cr.in0_d1 }} reset_row ;;
    SET LR4 CR0 ; INC LR6 1 ;;
reset_row:
    SET LR7 LR4 ;;
next_lane:
    DEC LR8 1 ; ADDBI LRD2 1 ;;
    BNE LR8 CR0 lane ;;
    LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.out_rows }} row ;;
    HALT ;;
