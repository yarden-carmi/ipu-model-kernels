    # Both operands must pass through MULT to reach ACC; these are arithmetic,
    # not staging copies. Input and output share the axis-3 lane layout.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BEQ {{ cr.last_row }} CR0 final ;;
loop:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.operand }} ; ADD LR4 LR1 CR0 ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR1 1 ; BLT.S LR1 {{ cr.penultimate_row }} loop ;;
final:
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    HALT ;;
