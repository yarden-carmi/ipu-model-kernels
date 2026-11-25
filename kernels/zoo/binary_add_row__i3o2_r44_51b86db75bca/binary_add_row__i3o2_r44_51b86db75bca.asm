    SET LR15 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    INC LR4 255 ; SET LR7 CR0 ; SET LR6 CR0 ;;
    INC LR4 129 ; INC LR5 128 ;;
    // Precede the one-hot row with a zero row in the cyclic buffer.
    MULT.VE LR15 CR0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.basis }} LR15 ;;
    LD.MULT.CYCLIC LR15 {{ cr.basis }} LR4 ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.unit }}.L {{ cr.qf_in0 }}.L {{ cr.basis }} LR15 ;;
    LD.MULT.CYCLIC LR15 {{ cr.basis }} LR15 ;;
tile:
    SET LR0 CR0 ;;
column:
    SET LR12 LR7 ; SET LR11 {{ cr.height }} ; SET LR4 CR0 ;;
    LD.MULT R1 LR0 {{ cr.operand }} ;;
    MULT.VE LR5 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_operand }}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.RC.VE LR4 LR0 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    INC LR12 1 ; DEC LR4 1 ; DEC LR11 1 ;;
    BNE LR11 CR0 gather ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR0 1 ; INC LR6 1 ;;
    BLT.S LR0 {{ cr.width }} column ;;
    ADD LR7 LR7 {{ cr.height }} ; BNE LR6 {{ cr.out_rows }} tile ;;
    HALT ;;
