    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
row:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.operand }} ; ADD LR4 LR1 CR0 ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR1 1 ; BLT.S LR1 {{ cr.last_row }} more ;;
    HALT ;;
more:
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ CR0 CR0 row ;;
