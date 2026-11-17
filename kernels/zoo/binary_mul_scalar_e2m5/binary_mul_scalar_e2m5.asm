{# Scalar stays in R0[0]; LR0 selects that scalar and cyclic slot zero.
   Stream resident dimension-3 lane rows in [0,1,2] row order.
   Each row is multiplied in FP32 and rounded only by its e2 store.
   Loading each input before its store also permits in-place execution. #}
    SET LR0 CR0 ;;
    LD.MULT R0 LR0 {{ cr.operand }} ;;
    SET LR1 CR0 ;;
row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
