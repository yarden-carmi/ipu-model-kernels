// Gather the transposed view into the accumulator, one destination lane at a time.
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
row:
    SET LR10 LR8 ; SET LR11 CR0 ;;
block:
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 LR7 ; SET LR5 LR10 ;;
    ADDB LRD0 LR7 ; SET LR6 CR0 ;;
gather:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR6 1 ;;
    MULT.VE LR13 CR1 0 LR13 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR5 LR5 {{ cr.step_rows }} ;;
    ADD LR4 LR4 {{ cr.step_lane }} ; ADDB LRD0 {{ cr.step_lane }} ; ADDBI LRD2 1 ;;
    BLT.S LR4 LR14 no_carry ;;
    DEC LR4 128 ; ADDBI LRD0 -128 ; INC LR5 1 ;;
no_carry:
    BLT.S LR6 LR14 gather ;;
    LD.MULT R0 LR9 {{ cr.in1 }} ; ADD LR10 LR10 {{ cr.out0_d1 }} ; INC LR11 1 ;;
    MULT.VE LR13 CR1 0 LR13 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; BLT.S LR11 {{ cr.blocks }} block ;;
    INC LR7 1 ; BEQ LR9 {{ cr.rows }} row_done ;;
    BLT.S LR7 LR14 row ;;
    SET LR7 CR0 ; INC LR8 1 ; B row ;;
row_done:
    BEQ LR9 {{ cr.packed_rows }} finish ;;
pad:
    MULT.VE LR13 CR0 0 LR13 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.empty }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.packed_rows }} pad ;;
finish:
    HALT ;;
