    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    INC LR1 128 ; SET LR7 CR0 ; SET LR9 CR0 ;;
group:
    SET LR4 CR0 ; ADD LR8 LR7 {{ cr.height }} ;;
column:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR5 LR7 ;;
    MULT.VE LR0 CR0 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; INC LR5 1 ;;
    ADDBI LRD2 1 ; BNE LR5 LR8 gather ;;
    LD.MULT R1 LR9 {{ cr.operand }} ;;
    MULT.VE LR1 CR1 0 LR0 {{ cr.output_ds }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; INC LR9 1 ;;
    INC LR6 1 ;;
    INC LR4 1 ;;
    BNE LR4 {{ cr.width }} column ;;
    SET LR7 LR8 ; BEQ LR8 {{ cr.input_rows }} done ;;
    BNE LR9 {{ cr.operand_rows }} group ;;
    SET LR9 CR0 ; BEQ CR0 CR0 group ;;
done:
    HALT ;;
