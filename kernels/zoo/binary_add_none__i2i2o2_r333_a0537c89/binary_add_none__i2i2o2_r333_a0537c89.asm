{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    INC LR11 128 ;;
batch:
    SET LR4 LR13 ; SET LR5 LR15 ;;
row:
    // The view starts at a + A*b and advances by A*B per column.
    SET LR6 CR0 ; SET LR7 LR4 ; SET LR10 LR12 ;;
origin_group:
    BLT.S LR7 {{ cr.span }} origin_lane ;;
    SUB LR7 LR7 {{ cr.span }} ; ADD LR6 LR6 {{ cr.span_rows }} ; B origin_group ;;
origin_lane:
    SET LR8 LR7 ;;
origin_normalize:
    BLT.S LR8 LR11 chunk ;;
    SUB LR8 LR8 LR11 ; INC LR6 1 ; B origin_normalize ;;
chunk:
    LD.MULT R1 LR3 {{ cr.in1 }} ; SET LR9 LR11 ;;
    INC LR3 1 ;;
element:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR8 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.one }}.L ; ADD LR6 LR6 {{ cr.step_rows }} ; ADD LR7 LR7 {{ cr.step_span }} ; DEC LR10 1 ;;
    MULT.EE LR9 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR2 {{ cr.one }}.L ; ADD LR8 LR8 {{ cr.lane_batch }}.L ;;
    INC LR2 1 ;;
    BLT.S LR2 LR11 advance ;;
    {{ store('CR15.L') }}
    INC LR1 1 ; SET LR2 CR0 ;;
advance:
    BEQ LR10 CR0 row_done ;;
    INC LR9 1 ; BLT.S LR7 {{ cr.span }} normalize ;;
    SUB LR7 LR7 {{ cr.span }} ; ADD LR8 LR8 LR14 ;;
normalize:
    BLT.S LR8 LR11 chunk_check ;;
    SUB LR8 LR8 LR11 ; INC LR6 1 ; B normalize ;;
chunk_check:
    // R1's index reaches 256 after its final lane.
    ADD LR0 LR11 LR11 ;;
    BNE LR9 LR0 element ; SET LR0 CR0 ;;
    B chunk ;;
row_done:
    ADD LR4 LR4 {{ cr.lane_batch }}.H ; DEC LR5 1 ;;
    BNE LR5 CR0 row ;;
    BEQ LR2 CR0 batch_padding ;;
    {{ store(cr.tail ~ '.L') }}
    INC LR1 1 ; SET LR2 CR0 ;;
batch_padding:
    SET LR7 {{ cr.full }}.H ;;
    BEQ LR7 CR0 next_batch ;;
padding_row:
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; DEC LR7 1 ;;
    INC LR1 1 ; BNE LR7 CR0 padding_row ;;
next_batch:
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.lane_batch }}.H batch ;;
    HALT ;;
