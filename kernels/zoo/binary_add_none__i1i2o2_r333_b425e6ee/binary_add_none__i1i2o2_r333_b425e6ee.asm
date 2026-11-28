// The view's element (j,k) is at storage offset k*d1+j.  Map that
// offset back to (offset/d2, offset%d2) in the handed in0 layout.
    INC LR12 128 ;;
row:
    SET LR6 LR15 ; SET LR4 CR0 ; SET LR5 CR0 ;;
divide_j:
    BLT.S LR6 {{ cr.in0_d2 }} divided_j ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; INC LR4 1 ; BEQ LR0 CR0 divide_j ;;
divided_j:
    SET LR7 LR6 ;;
multiply_row:
    BEQ LR7 CR0 normalize_j ;;
    ADD LR5 LR5 {{ cr.blocks }} ; DEC LR7 1 ; BEQ LR0 CR0 multiply_row ;;
normalize_j:
    BLT.S LR4 LR12 begin_row ;;
    SUB LR4 LR4 LR12 ; INC LR5 1 ; BEQ LR0 CR0 normalize_j ;;
begin_row:
    SET LR11 CR0 ; SET LR13 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
element:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
    ADDBI LRD2 1 ; INC LR11 1 ; INC LR13 1 ;;
    ADD LR6 LR6 {{ cr.rem_step }} ; ADD LR5 LR5 {{ cr.row_step }} ; ADD LR4 LR4 {{ cr.quot_step }} ;;
    BLT.S LR6 {{ cr.in0_d2 }} normalize ;;
    SUB LR6 LR6 {{ cr.in0_d2 }} ; SUB LR5 LR5 {{ cr.rollover }} ; INC LR4 1 ;;
normalize:
    BLT.S LR4 LR12 normalized ;;
    // d1 < 16384 and d2 >= 128, so this needs at most one subtraction.
    SUB LR4 LR4 LR12 ; INC LR5 1 ;;
normalized:
    BLT.S LR13 LR12 element ;;
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ;;
    BGE.S LR11 {{ cr.in0_d2 }} next_row ;;
    SET LR13 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ; BEQ LR0 CR0 element ;;
next_row:
    INC LR15 1 ;;
    BLT.S LR15 {{ cr.in0_d1 }} row ;;
    HALT ;;
