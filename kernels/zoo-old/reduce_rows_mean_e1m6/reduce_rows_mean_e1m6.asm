{#- Mean over the n rows of in0: one value per channel (rows run along the 128 lanes).

    in0 is [n, rb*128]: n positions in row order, the rows (channels) dimension
    split into rb lane blocks of 128, so position p, block b lives at row p*rb + b.
    The mean over dim0 is accumulated in FP32 in R_ACC: the reciprocal 1/n sits
    in R_CYCLIC (loaded once) and each input row (R1) is multiplied by it with
    MULT.RC.VV before ACC.ADD, so no intermediate roundtrip through NX8 is
    needed. Each output lane block b is stored with one ACTIVATE.QUANTIZE.
-#}
    SET LR0 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.recip }} LR0 ;;
    SET LR3 CR0 ;;
bloop:
    SET LR1 LR3 ;;
    LD.MULT R1 LR1 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ADD LR1 LR1 {{ cr.rb }} ;;
    SET LR4 {{ cr.n }} ;;
    DEC LR4 1 ;;
inner:
    LD.MULT R1 LR1 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ADD LR1 LR1 {{ cr.rb }} ;;
    DEC LR4 1 ;;
    BNE LR4 CR0 inner ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.rb }} bloop ;;
    HALT ;;
