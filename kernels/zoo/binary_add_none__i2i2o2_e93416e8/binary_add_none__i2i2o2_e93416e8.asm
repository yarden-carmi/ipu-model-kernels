    SET LR0 CR0 ;;
    SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
batch:
    SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    SET LR14 CR0 ;;
row:
    ADD LR4 LR10 LR13 ;;
    SET LR5 LR14 ;;
    SET LR15 CR0 ;;
chunk:
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
gather:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR5 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD6 LRD2 0 ;;
    ADDBI LRD2 1 ;;
    ADD LR4 LR4 {{ cr.step_row }} ;;
    ADD LR5 LR5 {{ cr.step_lane }} ;;
    BLT.S LR5 {{ cr.limit }} next ;;
    SUB LR5 LR5 {{ cr.limit }} ;;
    INC LR4 1 ;;
next:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.limit }} gather ;;
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ;;
    INC LR15 1 ;;
    BLT.S LR15 {{ cr.width_rows }} chunk ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.limit }} y_next ;;
    SET LR14 CR0 ;;
    INC LR13 1 ;;
y_next:
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.in0_d1 }} row ;;
    ADD LR10 LR10 {{ cr.batch_rows }} ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.in0_d0 }} batch ;;
    HALT ;;
