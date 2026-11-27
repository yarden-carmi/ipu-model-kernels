{% macro span(dst, remaining, size, axis) %}
    SET {{ dst }} {{ cr.four }} ; BNE {{ remaining }} {{ size }} {{ axis }}_left_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_left_done:
    BNE {{ remaining }} CR1 {{ axis }}_right_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_right_done:
{% endmacro %}

    SET LR7 CR0 ; SET LR14 CR0 ; SET LR15 {{ cr.in0_d0 }} ;;
batch:
    SET LR3 {{ cr.h }} ; SET LR0 CR0 ;;
source_y:
    {{ span('LR5', 'LR3', cr.h, 'y') }}
    SET LR4 {{ cr.w }} ; SET LR8 LR7 ; SET LR13 CR0 ;;
source_x:
    {{ span('LR6', 'LR4', cr.w, 'x') }}
    SET LR1 LR14 ; SET LR2 CR0 ; SET LR12 {{ cr.in0_d1 }} ;;
    ADD LR0 LR0 LR13 ;;
    SET LR10 CR0 ; SET LR11 CR0 ;;
channel:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.EE LR0 CR1 0 LR2 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD10 7 ;;
    ADDBI LRD10 1 ; ADD LR1 LR1 {{ cr.stride }} ; DEC LR12 1 ;;
    BNE LR12 CR0 channel ;;
    SUB LR0 LR0 LR13 ;;
    SET LR9 LR8 ; SET LR12 LR5 ;;
replica_y:
    SET LR1 LR9 ; SET LR2 LR6 ;;
replica_x:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; DEC LR2 1 ;;
    BNE LR2 CR0 replica_x ;;
    ADD LR9 LR9 {{ cr.out0_d3 }} ; DEC LR12 1 ;;
    BNE LR12 CR0 replica_y ;;
    BNE LR4 {{ cr.w }} next_x ;;
    SET LR7 LR9 ;;
next_x:
    ADD LR8 LR8 LR6 ; INC LR13 1 ; DEC LR4 1 ;;
    BNE LR4 CR0 source_x ;;
    ADD LR0 LR0 {{ cr.w }} ; DEC LR3 1 ;;
    BNE LR0 {{ cr.three_w }} y_not_full ;;
    SET LR0 CR0 ; INC LR14 1 ;;
y_not_full:
    BNE LR3 CR0 source_y ;;
    BEQ LR0 CR0 batch_aligned ;;
    INC LR14 1 ;;
batch_aligned:
    ADD LR14 LR14 {{ cr.batch_extra }} ; DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
