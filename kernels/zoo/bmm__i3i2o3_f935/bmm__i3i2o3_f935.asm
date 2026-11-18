    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR3 CR0 ;;
head:
    SET LR4 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    INC LR1 1 ;;
    LD.MULT R1 LR1 {{ cr.in0 }} ;;
    INC LR1 1 ;;
    SET LR7 LR2 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR11 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR8 1 ; ADD LR7 LR7 {{ cr.brows }} ;;
inner:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR11 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR8 1 ; ADD LR7 LR7 {{ cr.brows }} ;;
    BLT.S LR8 {{ cr.k }} inner ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.m }} row ;;
    INC.MODP2 LR11 {{ cr.n }} 7 ;;
    BNE LR11 CR0 same_pair ;;
    INC LR2 1 ;;
same_pair:
    INC LR9 1 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.b }} head ;;
    HALT ;;
