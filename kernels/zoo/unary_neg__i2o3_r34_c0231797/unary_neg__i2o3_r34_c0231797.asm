{#- out0[h,s] = [-in[s, h*128+64:+64], in[s, h*128:+64]]: R_CYCLIC holds the row twice, window at 64 rotates lanes; sign row multiplies. -#}
    SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR6 {{ cr.c64 }} ; SET LR7 {{ cr.c128 }} ;;
    LD.MULT R0 LR0 {{ cr.sgn }} ;;
outer:
    ADD LR1 LR3 CR0 ;;
    SET LR4 CR0 ;;
inner:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR7 ;;
    MULT.RC.VV LR6 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    ADD LR1 LR1 {{ cr.chunks }} ;;
    INC LR2 1 ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.out0_d2 }} inner ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.out0_d1 }} outer ;;
    HALT ;;
