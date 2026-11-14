{#- binary_mul_scalar_e3m4: out0[i] = in0[i] * const, scalar broadcast (op='mul', broadcast='scalar').
    One row of 128 elements per iteration; all lanes of the declared shape are active. -#}
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    SET LR5 {{ cr.rows }} ;;
full_loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ cr.const }} 0 LR0 {{ cr.ds_full }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_full }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
    ADD LR1 LR1 CR1 ; INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 LR5 full_loop ;;
    HALT ;;
