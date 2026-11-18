    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ;;
row:
    SET LR14 CR0 ;;
tile:
    ADD LR7 LR2 LR14 ; SET LR8 LR3 ; SET LR9 CR0 ;;
    SET LR6 LR5 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    B advance ;;
inner:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
advance:
    ADD LR7 LR7 {{ cr.nchunks }} ; INC LR9 1 ; INC.MODP2 LR8 CR1 7 ;;
    BNE LR8 CR0 same_chunk ;;
    INC LR6 1 ;;
same_chunk:
    BLT.S LR9 {{ cr.k }} inner ;;
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.nchunks }} store_full ;;
    ACTIVATE.QUANTIZE identity {{ cr.dstail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    B stored ;;
store_full:
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
stored:
    INC LR10 1 ;;
    BLT.S LR14 {{ cr.nchunks }} tile ;;
    ADD LR5 LR5 {{ cr.arows }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.m }} row ;;
    SET LR12 CR0 ;;
head_offset:
    ADD LR2 LR2 {{ cr.nchunks }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.k }} head_offset ;;
    INC LR11 1 ; ADD LR3 LR3 {{ cr.k }} ;;
normalize:
    SET LR12 CR0 ;;
    INC LR12 128 ;;
    BLT.S LR3 LR12 ready ;;
    SUB LR3 LR3 LR12 ; INC LR1 1 ;;
    B normalize ;;
ready:
    BLT.S LR11 {{ cr.b }} head ;;
    HALT ;;
