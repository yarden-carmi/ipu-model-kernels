{#- gemm (1x1 conv, BN folded into the weights) as a channel-lane gemm. Per input row: bias hi, bias lo, then for each
    input channel its hi and lo weight row, one word each, streamed through R_CYCLIC slot 0 (the next row is loaded in the
    word that multiplies the current one); the scalar is the channel read from R0.
    LR1 = -1 (the LR instructions of a word run before its load and multiply, so the scalar of the second word of a
    channel is LR12, stepped in the first word). -#}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    DEC LR1 1 ;;
row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR8 LR1 ; SET LR9 CR0 ; SET LR12 LR1 ;;
    LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dsn }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.dsn }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ;;
chan:
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.dsn }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ; INC LR12 1 ;;
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.dsn }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR8 {{ cr.w }} LR0 ; INC LR8 1 ; INC LR9 1 ; BLT.S LR9 {{ cr.km1 }} chan ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsn }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR2 1 ;;
    INC LR3 1 ; BLT.S LR2 {{ cr.m }} row ;;
    HALT ;;
