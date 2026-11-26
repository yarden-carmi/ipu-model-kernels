    SET LR0 CR0 ;;
row:
    LD.MULT.CYCLIC LR0 {{ cr.in0 }} LR1 ;;
    MULT.RC.VE LR1 CR1 0 LR1 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ; BLT.S LR0 {{ cr.penultimate }} row ;;
    HALT ;;
