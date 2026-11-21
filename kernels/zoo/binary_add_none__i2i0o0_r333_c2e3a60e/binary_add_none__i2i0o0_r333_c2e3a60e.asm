{# Traverse the view in [2,1,0] order, which is forward storage order
   for in0. Each output row holds one contiguous dimension-0 group. #}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    SET LR6 CR0 ;;
    SET LR3 {{ cr.row_width }} ;;
    BLT.S CR0 {{ cr.block_tail }} padded ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
row:
    ADD LR4 LR2 {{ cr.out0_d0 }} ;;
    SET LR5 LR1 ;;
    INC LR5 1 ;;
    BLT.S LR4 {{ cr.crossing }} add_row ;;
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR3 ;;
add_row:
    LD.MULT R1 LR0 {{ cr.in1 }} ;;
    MULT.RC.VE LR2 CR1 0 LR6 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR3 CR1 0 LR6 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
    BLT.S LR0 {{ cr.out_rows }} advance ;;
    HALT ;;
advance:
    SET LR2 LR4 ;;
    BLT.S LR2 {{ cr.row_width }} row ;;
    SUB LR2 LR2 {{ cr.row_width }} ; SET LR1 LR5 ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR6 ;;
    BEQ LR6 CR0 row ;;

{# If an input block ends in padding, gather only its live elements.
   LR1/LR2 are the physical row/lane; LR7 counts live elements left. #}
padded:
    SET LR7 {{ cr.block_elements }} ;;
    SET LR12 CR0 ;;
gather_row:
    SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
gather_lane:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.EE LR2 CR1 0 LR6 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD8 LRD10 7 ;;
    ADDBI LRD10 1 ;;
    INC LR12 1 ;;
    SUB LR7 LR7 CR1 ;;
    BEQ LR7 CR0 block_end ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.row_width }} gathered ;;
    BEQ LR6 CR0 next_input_row ;;
block_end:
    SET LR7 {{ cr.block_elements }} ;;
next_input_row:
    INC LR1 1 ;;
    SET LR2 CR0 ;;
gathered:
    BLT.S LR12 {{ cr.out0_d0 }} gather_lane ;;
    LD.MULT R1 LR0 {{ cr.in1 }} ;;
    MULT.VE LR3 CR1 0 LR6 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    SET LR12 CR0 ;;
    INC LR0 1 ;;
    BLT.S LR0 {{ cr.out_rows }} gather_row ;;
    HALT ;;
