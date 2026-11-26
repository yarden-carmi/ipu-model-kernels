{# For each (batch, column pair, packed lane), gather one output row.
   The packed lane runs through all channels of each of the two columns. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR6 CR0 ;;
batch:
    SET LR3 CR0 ; SET LR4 LR2 ;;
column_pair:
    SET LR5 CR0 ;;
channel:
    SET LR7 LR4 ; SET LR8 CR0 ;;
    DEC LR8 1 ;;
height:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    INC LR8 1 ; ADD LR7 LR7 {{ cr.pairs }} ; MULT.EE LR5 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR8 {{ cr.single }}.L ; BLT.S LR8 {{ cr.penultimate_height }} height ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.packed_lanes }} channel ;;
    INC LR3 1 ; INC LR4 1 ;;
    BLT.S LR3 {{ cr.pairs }} column_pair ;;
    INC LR1 1 ; ADD LR2 LR2 {{ cr.batch_stride }} ;;
    BLT.S LR1 {{ cr.in0_d0 }} batch ;;
    HALT ;;
