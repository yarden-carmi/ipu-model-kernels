{#- binary_add_none_e2m5: out0[i] = in0[i] + in1[i], elementwise (op='add', broadcast='none').
    One row of 128 elements per iteration; in0 in R0, in1 in R1, both added into
    the accumulator via MULT.VE with scalar 1 (CR1); padding lanes (none here,
    numel is a multiple of 128) would be masked by ds_full. -#}
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR5 CR0 ;;
    INC LR5 128 ;;
    SET LR6 {{ cr.rows }} ;;
full_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR2 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_full }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR5 CR1 0 LR0 {{ cr.ds_full }}.L {{ cr.qf }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_full }}.L {{ cr.qf }}.L {{ cr.out0 }} LR3 ;;
    ADD LR1 LR1 CR1 ; INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 LR6 full_loop ;;
    HALT ;;
