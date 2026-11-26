    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
    INC LR3 128 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR2 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR2 1 ;;
    BEQ LR1 {{ cr.rows }} done ;;
    BLT.S LR2 {{ cr.operand_rows }} row ;;
    SET LR2 CR0 ;;
    BEQ CR0 CR0 row ;;
done:
    HALT ;;
