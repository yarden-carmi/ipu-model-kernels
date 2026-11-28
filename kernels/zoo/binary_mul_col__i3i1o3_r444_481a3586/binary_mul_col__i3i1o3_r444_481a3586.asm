    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SUB LR5 LR5 CR1 ;;
scale_block:
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    INC LR3 1 ;;
channel:
    LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR1 ;;
    MULT.RC.VE LR1 LR4 0 LR1 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR0 1 ; INC LR2 1 ;;
    BEQ LR2 {{ cr.inner_end }} last_channel ;;
    INC.MODP2 LR4 CR1 7 ; BNE LR4 {{ cr.wrap }} channel ;;
    B scale_block ;;
last_channel:
    INC.MODP2 LR4 CR1 7 ; LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR1 ;;
    MULT.RC.VE LR1 LR4 0 LR1 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR0 1 ; SET LR2 CR0 ;;
    SET LR4 CR0 ; SET LR3 CR0 ;;
    BLT.S LR0 {{ cr.total }} scale_block ;;
done:
    HALT ;;
