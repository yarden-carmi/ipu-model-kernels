{% macro span(dst, remaining, size, axis) %}
    SET {{ dst }} {{ cr.four }} ; BNE {{ remaining }} {{ size }} {{ axis }}_first_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_first_done:
    BNE {{ remaining }} CR1 {{ axis }}_last_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_last_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR7 CR0 ; SET LR15 {{ cr.in0_d0 }} ;;
batch:
    SET LR13 {{ cr.h }} ;;
source_y:
    {{ span('LR14', 'LR13', cr.h, 'y') }}
    SET LR12 {{ cr.w }} ; SET LR6 CR0 ; SET LR8 LR7 ;;
source_x:
    {{ span('LR11', 'LR12', cr.w, 'x') }}
    SET LR4 LR5 ; SET LR3 CR0 ;;
    MULT.EE LR6 CR0 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    // The last byte of LRD2 selects the output channel lane.
    MULT.EE LR6 CR1 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    INC LR4 1 ; ADD LR3 LR3 {{ cr.lane_step }} ;;
    BNE LR3 {{ cr.lane_end }} channel ;;
    SET LR9 LR8 ; SET LR4 LR14 ;;
replica_y:
    SET LR10 LR9 ; SET LR3 LR11 ;;
replica_x:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; DEC LR3 1 ;;
    BNE LR3 CR0 replica_x ;;
    ADD LR9 LR9 {{ cr.out0_d3 }} ; DEC LR4 1 ;;
    BNE LR4 CR0 replica_y ;;
    BNE LR12 {{ cr.w }} next_x ;;
    SET LR7 LR9 ;;
next_x:
    ADD LR8 LR8 LR11 ; INC LR6 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 source_x ;;
    ADD LR5 LR5 {{ cr.in0_d1 }} ; DEC LR13 1 ;;
    BNE LR13 CR0 source_y ;;
    DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
