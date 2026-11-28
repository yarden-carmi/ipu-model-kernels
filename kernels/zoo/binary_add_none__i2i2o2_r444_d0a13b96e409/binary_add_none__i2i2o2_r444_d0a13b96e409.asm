    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR13 ; LD.MULT R0 LR5 {{ cr.in0 }} ; BGE.S LR5 {{ cr.limit }} last ;;
    SET LR7 CR0 ;;
loop:
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ; INC LR7 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; LD.MULT R0 LR7 {{ cr.in0 }} ; INC LR5 1 ; BLT.S LR5 {{ cr.loop_limit }} loop ;;
last:
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ; INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; HALT ;;
