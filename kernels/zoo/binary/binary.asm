{#- out0 = in0 + in1, elementwise, one row of 128 per pass. There is no vector add: each row passes through the
    multiplier times CR1 (1.0), and the accumulator sums the two. -#}
    SET LR0 CR0 ; SET LR1 CR0 ;;
row_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row_loop ;;
    HALT ;;
