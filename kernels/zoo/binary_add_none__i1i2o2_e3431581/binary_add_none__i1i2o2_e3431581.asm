    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
loop:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.blocks }} full ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    SET LR3 CR0 ;;
    ADD LR4 LR4 {{ cr.pstep }} ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.out0_d1 }} next ;;
    SET LR7 CR0 ; ADD LR6 LR6 {{ cr.blocks }} ;;
    SET LR4 LR6 ;;
    BEQ LR0 CR0 next ;;
full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR4 1 ;;
next:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;
