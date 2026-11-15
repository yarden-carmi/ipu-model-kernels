    SET LR0 CR0 ; SET LR1 CR0 ;;
loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 {{ cr.minus_one }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;
