    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ;;
row:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR8 LR3 ; SET LR9 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR8 1 ; INC LR9 1 ; ADD LR7 LR7 {{ cr.nchunks }} ;;
inner:
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR8 1 ; INC LR9 1 ; ADD LR7 LR7 {{ cr.nchunks }} ;;
    BLT.S LR9 {{ cr.k }} inner ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.nchunks }} tile ;;
    ADD LR5 LR5 {{ cr.arows }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.m }} row ;;
    ADD LR2 LR2 {{ cr.headstride }} ;;
    INC LR11 1 ;;
    INC.MODP2 LR3 {{ cr.k }} 7 ;;
    BNE LR3 CR0 same_input_row ;;
    INC LR1 1 ;;
same_input_row:
    BLT.S LR11 {{ cr.b }} head ;;
    HALT ;;
