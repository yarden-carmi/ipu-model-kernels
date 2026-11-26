{% macro span(dst, remaining, size, axis) %}
    SET {{ dst }} {{ cr.four }} ; BNE {{ remaining }} {{ size }} {{ axis }}_left_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_left_done:
    BNE {{ remaining }} CR1 {{ axis }}_right_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_right_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR14 CR0 ; SET LR15 CR0 ;;
batch:
    SET LR13 {{ cr.h }} ;;
source_y:
    {{ span('LR5', 'LR13', cr.h, 'y') }}
    SET LR4 {{ cr.w }} ; SET LR8 LR7 ; SET LR15 CR0 ;;
source_x:
    {{ span('LR6', 'LR4', cr.w, 'x') }}
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR9 LR14 ;;
    SET LR10 CR0 ;;
    ADD LR11 LR1 LR15 ;;
gather:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR11 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR9 LR9 {{ cr.channel_stride }} ;;
    ADDBI LRD2 1 ; INC LR10 1 ;;
    BNE LR10 {{ cr.out0_d1 }} gather ;;
    SET LR9 LR8 ; SET LR11 LR5 ;;
replica_y:
    SET LR10 LR9 ; SET LR12 LR6 ;;
replica_x:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 replica_x ;;
    ADD LR9 LR9 {{ cr.out0_d3 }} ; DEC LR11 1 ;;
    BNE LR11 CR0 replica_y ;;
    BNE LR4 {{ cr.w }} next_x ;;
    SET LR7 LR9 ;;
next_x:
    ADD LR8 LR8 LR6 ; INC LR15 1 ; DEC LR4 1 ;;
    BNE LR4 CR0 source_x ;;
    ADD LR1 LR1 {{ cr.w }} ; DEC LR13 1 ;;
    BNE LR1 {{ cr.eight }} y_continue ;;
    SET LR1 CR0 ; INC LR14 1 ;;
y_continue:
    BNE LR13 CR0 source_y ;;
    ADD LR14 LR14 {{ cr.batch_skip }} ;;
    BNE LR14 {{ cr.total_rows }} batch ;;
    HALT ;;
