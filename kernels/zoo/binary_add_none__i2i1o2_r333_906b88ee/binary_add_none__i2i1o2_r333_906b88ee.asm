    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
    SET LR8 CR0 ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
row:
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR11 CR0 ;;
    ADD LR12 LR8 LR7 ;;
gather:
    LD.MULT R0 LR12 {{ cr.in1 }} ;;
    MULT.EE LR6 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ;;
    INC LR11 1 ;;
    INC LR12 1 ;;
    ADD LR13 LR7 LR11 ;;
    BGE.S LR13 {{ cr.in0_d2 }} gathered ;;
    BLT.S LR11 LR14 gather ;;
gathered:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.width }} full ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    SET LR4 CR0 ;;
    SET LR7 CR0 ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.in0_d1 }} next ;;
    SET LR6 CR0 ;;
    ADD LR8 LR8 {{ cr.in0_d2 }} ;;
    BEQ CR0 CR0 next ;;
full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR7 128 ;;
next:
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.rows }} row ;;
    HALT ;;
