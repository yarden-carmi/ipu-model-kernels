    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
plane:
    SET LR3 CR0 ;;
column:
    SET LR4 CR0 ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.last_channel }} CR0 channel_tail ;;
channel:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ADD LR5 LR1 CR0 ; INC LR1 1 ; INC LR4 1 ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR4 {{ cr.last_channel }} channel ;;
channel_tail:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.period }} column ;;
    BLT.S LR1 {{ cr.rows }} plane ;;
    HALT ;;
