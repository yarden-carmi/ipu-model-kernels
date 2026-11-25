    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ;;
period:
    SET LR3 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR3 1 ;;
    INC LR1 1 ;;
    BEQ LR1 {{ cr.rows }} done ;;
    BLT.S LR3 {{ cr.operand_rows }} row ;;
    BEQ CR0 CR0 period ;;
done:
    HALT ;;
