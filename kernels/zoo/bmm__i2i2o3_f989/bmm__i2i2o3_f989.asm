    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 LR15 ; SET LR3 CR0 ; SET LR14 CR0 ;;
    SET LR15 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
transpose_k:
    SET LR5 LR2 ; SET LR6 CR0 ;;
transpose_tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
transpose_lane:
    LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.EE LR1 CR1 0 LR14 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD14 LRD12 0 ;;
    ADDBI LRD12 1 ; ADD LR5 LR5 {{ cr.arows }} ; INC LR7 1 ;;
    BLT.S LR7 LR9 transpose_lane ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L {{ cr.trans }} LR3 ;;
    INC LR3 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.nchunks }} transpose_tile ;;
    INC LR0 1 ; INC.MODP2 LR1 CR1 7 ;;
    BNE LR1 CR0 transpose_same ;;
    INC LR2 1 ;;
transpose_same:
    BLT.S LR0 LR4 transpose_k ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ;;
row:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR8 LR3 ; SET LR9 CR0 ;;
    LD.MULT.CYCLIC LR7 {{ cr.trans }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR8 1 ; INC LR9 1 ; ADD LR7 LR7 {{ cr.nchunks }} ;;
inner:
    LD.MULT.CYCLIC LR7 {{ cr.trans }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR8 1 ; INC LR9 1 ; ADD LR7 LR7 {{ cr.nchunks }} ;;
    BLT.S LR9 {{ cr.k }} inner ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.nchunks }} tile ;;
    ADD LR5 LR5 {{ cr.arows }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.m }} row ;;
    ADD LR2 LR2 {{ cr.headstride }} ; INC LR11 1 ;;
    INC.MODP2 LR3 {{ cr.k }} 7 ;;
    BNE LR3 CR0 same_input_row ;;
    INC LR1 1 ;;
same_input_row:
    BLT.S LR11 {{ cr.b }} head ;;
    HALT ;;
