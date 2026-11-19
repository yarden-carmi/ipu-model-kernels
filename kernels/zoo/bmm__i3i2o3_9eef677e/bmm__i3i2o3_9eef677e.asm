    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ;;
row:
    SET LR7 LR2 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR6 LR1 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR11 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    B advance ;;
inner:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR11 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
advance:
    INC LR9 1 ; ADD LR7 LR7 {{ cr.brows }} ; INC.MODP2 LR8 CR1 7 ;;
    BNE LR8 CR0 same_chunk ;;
    INC LR6 1 ;;
same_chunk:
    BLT.S LR9 {{ cr.k }} inner ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR4 1 ; ADD LR1 LR1 {{ cr.kc }} ;;
    BLT.S LR4 {{ cr.m }} row ;;
    INC.MODP2 LR11 {{ cr.n }} 7 ;;
    BNE LR11 CR0 same_pair ;;
    INC LR2 1 ;;
same_pair:
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.b }} head ;;
    HALT ;;
