    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR10 CR0 ;;
channel:
    SET LR3 CR0 ; SET LR4 CR0 ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.w }} LR0 ; SET LR7 CR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ;;
    LD.MULT R0 LR1 {{ cr.w }} ;;
    INC LR1 1 ;;
    LD.MULT R1 LR1 {{ cr.w }} ;;
    DEC LR1 2 ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
pixel:
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.kds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR7 {{ cr.kds }}.L ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ cr.kds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR7 {{ cr.kds }}.L ; LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; INC LR4 1 ;;
    INC LR7 1 ; BLT.S LR7 {{ cr.last }} pixel ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.kds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR7 {{ cr.kds }}.L ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ cr.kds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR7 {{ cr.kds }}.L ; INC LR4 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.width }} row ;;
    INC LR1 3 ; INC LR10 1 ;;
    BLT.S LR10 {{ cr.n }} channel ;;
    HALT ;;
