    SET LR2 CR0 ;;
row:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.in_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} row ;;
    HALT ;;
