    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
row:
    # Physical row order is spatial height, then channel.
    LD.MULT R0 LR2 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.inner }} next ;;
    SET LR2 CR0 ;;
next:
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
