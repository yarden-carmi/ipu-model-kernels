{#- binary_add_none_e3m4: out0 = in0 + in1, e3m4, broadcast none.

    One row per iteration: in0's row is loaded into R0 and the constant
    operand in1's row into R1. Two MULT.VE passes by the CR scalar 1.0
    (CR1) put in0 (Ra offset 0) and in1 (Ra offset 128) through the
    multiplier; the first ACC.ADD.FIRST, the second ACC.ADD, so R_ACC
    holds in0 + in1 in FP32. ACTIVATE.QUANTIZE identity stores it in the
    run's format (qf). in1 has 768 rows; LR5 walks it and resets to 0
    when it reaches in1_rows, so in1 is reused cyclically for larger
    numel. A partial last row is stored with the DS half ds_tail so
    padding lanes are written zero. -#}
    SET LR0 CR0 ;;                 # Ra offset 0
    SET LR1 CR0 ;;                 # row index (in0 and out0 share rows)
    SET LR3 CR0 ;;
    INC LR3 128 ;;                 # Ra offset 128 -> R1
    SET LR5 CR0 ;;                 # in1 row counter
full_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    INC LR5 1 ;;
    BNE LR5 {{ cr.in1_rows }} noreset ;;
    SET LR5 CR0 ;;
noreset:
    BLT.S LR1 {{ cr.full }} full_loop ;;
    BGE.S LR1 {{ cr.rows }} done ;;
tail:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
done:
    HALT ;;
