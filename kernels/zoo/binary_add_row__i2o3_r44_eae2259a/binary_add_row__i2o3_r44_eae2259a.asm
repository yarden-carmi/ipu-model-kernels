    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
batch:
    SET LR4 LR3 ; SET LR5 CR0 ;;
head:
    SET LR6 CR0 ;;
row:
    // Gather into the accumulator without quantizing the transposed values.
    SET LR7 LR4 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR10 CR0 ;;
gather:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD8 7 ; ADD LR7 LR7 {{ cr.in0_d1 }} ; INC LR10 1 ;;
    ADDBI LRD8 1 ; BLT.S LR10 {{ cr.in0_d3 }} gather ;;
    LD.MULT R0 LR2 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR2 1 ; INC LR6 1 ;;
    INC LR1 1 ;;
    BEQ LR1 {{ cr.rows }} done ;;
    BLT.S LR2 {{ cr.operand_rows }} next_row ;;
    SET LR2 CR0 ;;
next_row:
    BLT.S LR6 {{ cr.in0_d2 }} row ;;
    INC LR4 1 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.in0_d1 }} head ;;
    ADD LR3 LR3 {{ cr.batch_stride }} ; B batch ;;
done:
    HALT ;;
