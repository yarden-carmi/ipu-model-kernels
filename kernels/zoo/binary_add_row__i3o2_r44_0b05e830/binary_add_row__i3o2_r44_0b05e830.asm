    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR11 CR0 ;;
    INC LR11 128 ;;

// Walk (batch, column, channel); gather one column into accumulator lanes.
row:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 LR7 ;;
    SET LR10 CR0 ; LD.MULT R1 LR5 {{ cr.operand }} ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; INC LR10 1 ; INC LR6 1 ;;
    BLT.S LR10 {{ cr.in0_d2 }} gather ;;

    MULT.VE LR11 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR8 1 ; SET LR7 LR6 ;;
    BEQ LR5 {{ cr.rows }} done ;;
    BLT.S LR8 {{ cr.in0_d1 }} row ;;
    SET LR8 CR0 ; INC LR4 1 ; SET LR7 LR9 ;;
    BLT.S LR4 {{ cr.in0_d3 }} row ;;
    SET LR4 CR0 ; SET LR9 LR6 ; SET LR7 LR6 ;;
    BEQ CR0 CR0 row ;;
done:
    HALT ;;
