{# Contiguous dimension-2 lane layout: add matching physical rows in FP32,
   then round once to e2. The final store zeros inactive tail lanes. #}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
loop:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ;;
    BLT.S LR1 {{ cr.last }} full ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds_tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    HALT ;;
full:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;
