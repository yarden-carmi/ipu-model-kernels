    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
mean_loop:
    LD.MULT R0 LR2 {{ cr.mean }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.blocks }} mean_next ;;
    SET LR2 CR0 ;;
mean_next:
    BLT.S LR1 {{ cr.rows }} mean_loop ;;
    HALT ;;
