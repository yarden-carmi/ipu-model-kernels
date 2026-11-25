    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
batch:
    SET LR4 CR0 ; ADD LR5 LR1 {{ cr.batch_pitch }} ;;
column:
    SET LR6 LR1 ; BNE {{ cr.operand_stride }} CR0 plane ;;
    SET LR3 LR4 ;;
plane:
    SET LR12 CR0 ; SET LR13 CR0 ; ADD LR7 LR6 {{ cr.in0_d2 }} ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD12 LRD12 7 ; INC LR6 1 ;;
    ADDBI LRD12 1 ; BLT.S LR6 LR7 gather ;;
    LD.MULT R0 LR3 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; ADD LR3 LR3 {{ cr.operand_stride }} ;;
    INC LR2 1 ;;
    BLT.S LR6 LR5 plane ;;
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.in0_d3 }} column ;;
    SET LR1 LR5 ;;
    BLT.S LR1 {{ cr.input_rows }} batch ;;
    HALT ;;
