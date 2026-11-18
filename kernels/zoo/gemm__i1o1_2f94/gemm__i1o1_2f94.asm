    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR4 CR0 ;;
rows:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    SET LR5 CR0 ;;
    SET LR2 CR0 ;;
blocks:
    SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR2 1 ; INC LR3 1 ;;
depth:
    LD.MULT.CYCLIC LR2 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.k }} depth ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.NB }} blocks ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.m }} rows ;;
    HALT ;;
