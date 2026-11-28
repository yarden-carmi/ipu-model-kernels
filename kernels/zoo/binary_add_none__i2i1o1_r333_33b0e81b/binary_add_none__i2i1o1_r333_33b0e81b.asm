    SET LR13 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
    SET LR7 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR11 CR0 ;;
column:
    SET LR4 LR8 ; SET LR5 LR9 ; SET LR10 CR0 ;;
block:
    MULT.VE LR13 CR0 0 LR13 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR0 CR0 ; SET LR1 {{ cr.indices }} ; SET LR2 CR0 ;;
    SET LR3 {{ cr.indices }} ;;
    ADDB LRD0 LR5 ; SET LR6 CR0 ; SET LR12 LR14 ;;
    BNE LR10 {{ cr.last_block }} preload ;;
    SET LR12 LR15 ;;
preload:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
gather:
    MULT.VE LR13 CR1 0 LR13 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 4 ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR6 4 ; INC LR5 4 ;;
    ADDBI LRD0 4 ; ADDBI LRD2 4 ; BLT.S LR5 LR14 no_carry ;;
    SET LR5 CR0 ; ADDBI LRD0 -128 ; INC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
no_carry:
    BLT.S LR6 LR12 gather ;;
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
    MULT.VE LR13 CR1 0 LR13 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    BEQ LR10 {{ cr.last_block }} store_tail ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    BEQ CR0 CR0 stored ;;
store_tail:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
stored:
    INC LR7 1 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.blocks }} block ;;
    ADD LR8 LR8 {{ cr.step_rows }} ; ADD LR9 LR9 {{ cr.step_lane }} ; INC LR11 1 ;;
    BLT.S LR9 LR14 next_column ;;
    DEC LR9 128 ; INC LR8 1 ;;
next_column:
    BLT.S LR11 {{ cr.columns }} column ;;
    HALT ;;
