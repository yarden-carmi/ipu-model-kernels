    SET LR0 CR0 ; SET LR1 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.factor }} LR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.out0_d0 }} row ;;
    HALT ;;
