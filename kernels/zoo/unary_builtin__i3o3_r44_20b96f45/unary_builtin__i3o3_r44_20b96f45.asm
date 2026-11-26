    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
packed_row:
    SET LR3 CR0 ; LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
item:
    {# The read window starts at the packed item's first lane; the store zeros the rest. #}
    MULT.RC.VE LR3 CR1 0 LR0 {{ cr.input_active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
    ADD LR3 LR3 {{ cr.in0_d3 }} ; BLT.S LR3 {{ cr.last_lane }} item ;;
    INC LR1 1 ; BLT.S LR1 {{ cr.last_row }} packed_row ;;
    HALT ;;
