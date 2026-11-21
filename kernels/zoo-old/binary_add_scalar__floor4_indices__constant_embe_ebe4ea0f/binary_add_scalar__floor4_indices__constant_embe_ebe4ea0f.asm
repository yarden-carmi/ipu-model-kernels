    LD.MULT R0 LR0 {{ cr.prior }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
prior_loop:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BNE LR1 {{ cr.rows0 }} prior_loop ;;
zero_loop:
    LD.MULT R0 LR3 {{ cr.w }} ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR2 ;;
    INC LR2 1 ;;
    INC LR3 1 ;;
    BNE LR3 {{ cr.blocks }} keep_block ;;
    SET LR3 CR0 ;;
keep_block:
    BNE LR2 {{ cr.rows1 }} zero_loop ;;
    HALT ;;
