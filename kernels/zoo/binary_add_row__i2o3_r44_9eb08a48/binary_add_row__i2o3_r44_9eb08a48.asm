    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    INC LR1 128 ; SET LR9 CR0 ;;
plane:
    ADD LR8 LR7 {{ cr.in0_d3 }} ; SET LR10 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
row:
    SET LR4 CR0 ; SET LR5 CR0 ; ADD LR6 LR7 CR0 ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ; INC LR6 1 ;;
    ADDBI LRD4 1 ; BLT.S LR6 LR8 gather ;;
    LD.MULT R1 LR10 {{ cr.operand }} ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; INC LR10 1 ; ADDBI LRD2 1 ;;
    BLT.S LR10 {{ cr.in0_d2 }} row ;;
    ADD LR7 LR8 CR0 ; BLT.S LR8 {{ cr.rows }} plane ;;
    HALT ;;
