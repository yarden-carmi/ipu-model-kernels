    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    SET LR8 CR0 ; SET LR10 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
feature:
    SET LR5 LR2 ; SET LR6 CR0 ; SET LR4 CR0 ;;
tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
lane:
    BGE.S LR4 {{ cr.in0_d1 }} zero ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR1 CR1 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD12 0 ;;
    B next ;;
zero:
    MULT.EE LR1 CR0 0 LR14 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD12 0 ;;
next:
    ADDBI LRD12 1 ; ADD LR5 LR5 {{ cr.stride }} ; INC LR7 1 ;;
    INC LR4 1 ;;
    BLT.S LR7 LR9 lane ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.chunks }} last_tile ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    B stored ;;
last_tile:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
stored:
    INC LR3 1 ;;
    BLT.S LR6 {{ cr.chunks }} tile ;;
    INC LR0 1 ; INC LR8 1 ; INC.MODP2 LR1 CR1 7 ;;
    BLT.S LR8 {{ cr.in0_d2 }} within_batch ;;
    SET LR8 CR0 ; SET LR1 CR0 ; ADD LR10 LR10 {{ cr.batchrows }} ;;
    SET LR2 LR10 ; B same ;;
within_batch:
    BNE LR1 CR0 same ;;
    INC LR2 1 ;;
same:
    BLT.S LR0 {{ cr.features }} feature ;;
    HALT ;;
