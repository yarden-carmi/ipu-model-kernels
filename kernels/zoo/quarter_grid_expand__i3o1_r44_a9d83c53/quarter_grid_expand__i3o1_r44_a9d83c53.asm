// Each input cell contributes four replicas, plus any halo touching it.
{% macro span(dst, remaining, size, axis) %}
    SET {{ dst }} CR1 ;;
    INC {{ dst }} 3 ; BNE {{ remaining }} {{ size }} {{ axis }}_first_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_first_done:
    BNE {{ remaining }} CR1 {{ axis }}_last_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_last_done:
{% endmacro %}

    SET LR0 {{ cr.in0_d0 }} ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR15 CR0 ;;
batch:
    SET LR8 {{ cr.h }} ;;
source_y:
    {{ span('LR10', 'LR8', cr.h, 'y') }}
    SET LR9 {{ cr.w }} ; SET LR12 LR15 ;;
    // LR4: first lane of this input y; LR5: packed row for channel zero.
    SET LR7 LR4 ;;
source_x:
    {{ span('LR11', 'LR9', cr.w, 'x') }}
    SET LR3 CR0 ; SET LR6 LR5 ; SET LR13 LR7 ;;
    SET LR14 {{ cr.in0_d1 }} ;;
gather_channel:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    // Scatter one selected input element into the next output channel lane.
    MULT.EE LR13 CR1 0 LR1 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; ADD LR6 LR6 {{ cr.channel_rows }} ; ADD LR13 LR13 {{ cr.channel_lanes }} ;;
    DEC LR14 1 ; BLT.S LR13 {{ cr.packed_width }} channel_ready ;;
    SUB LR13 LR13 {{ cr.packed_width }} ; INC LR6 1 ;;
channel_ready:
    BNE LR14 CR0 gather_channel ;;

    SET LR6 LR12 ; SET LR14 LR10 ;;
replica_y:
    SET LR13 LR6 ; SET LR2 LR11 ;;
replica_x:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; DEC LR2 1 ;;
    BNE LR2 CR0 replica_x ;;
    ADD LR6 LR6 {{ cr.out0_d3 }} ; DEC LR14 1 ;;
    BNE LR14 CR0 replica_y ;;
    BNE LR9 {{ cr.w }} next_x ;;
    SET LR15 LR6 ;;
next_x:
    ADD LR12 LR12 LR11 ; INC LR7 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 source_x ;;
    ADD LR4 LR4 {{ cr.in0_d3 }} ; DEC LR8 1 ;;
    BNE LR4 {{ cr.packed_width }} y_ready ;;
    SET LR4 CR0 ; INC LR5 1 ;;
y_ready:
    BNE LR8 CR0 source_y ;;
    DEC LR0 1 ;;
    BNE LR0 CR0 batch ;;
    HALT ;;
