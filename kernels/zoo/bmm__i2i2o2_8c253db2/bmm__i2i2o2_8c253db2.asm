    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ;;
column:
    SET LR5 CR0 ;;
chunk:
    ADD LR6 LR1 LR5 ; SET LR7 LR2 ; SET LR8 CR0 ;;
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR11 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR8 1 ; ADD LR6 LR6 {{ cr.mc }} ; ADD LR7 LR7 {{ cr.brows }} ;;
    BGE.S LR8 {{ cr.k }} store ;;
inner:
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR11 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR8 1 ; ADD LR6 LR6 {{ cr.mc }} ; ADD LR7 LR7 {{ cr.brows }} ;;
    BLT.S LR8 {{ cr.k }} inner ;;
store:
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.mc }} full ;;
    ACTIVATE.QUANTIZE identity {{ cr.dstail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    B stored ;;
full:
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
stored:
    INC LR10 1 ;;
    BLT.S LR5 {{ cr.mc }} chunk ;;
    INC LR11 1 ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.n }} column ;;
    INC.MODP2 LR11 LR0 7 ;;
    BNE LR11 CR0 same_pair ;;
    INC LR2 1 ;;
same_pair:
    ADD LR1 LR1 LR15 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.b }} head ;;
    HALT ;;
