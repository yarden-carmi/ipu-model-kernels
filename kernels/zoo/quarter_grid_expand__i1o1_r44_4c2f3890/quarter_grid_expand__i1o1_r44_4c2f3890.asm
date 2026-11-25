// Repeat four times, plus one for each clamped halo touching this cell.
{% macro span(dst, remaining, size, axis) %}
    SET {{ dst }} {{ cr.four }} ; BNE {{ remaining }} {{ size }} {{ axis }}_left_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_left_done:
    BNE {{ remaining }} CR1 {{ axis }}_right_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_right_done:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR7 CR0 ; SET LR13 {{ cr.in0_d0 }} ;;
batch:
    SET LR3 {{ cr.h }} ;;
source_y:
    {{ span('LR5', 'LR3', cr.h, 'y') }}
    SET LR4 {{ cr.w }} ; SET LR8 LR7 ;;
source_x:
    {{ span('LR6', 'LR4', cr.w, 'x') }}
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR9 LR8 ; SET LR11 LR5 ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
replica_y:
    SET LR10 LR9 ; SET LR12 LR6 ;;
replica_x:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 replica_x ;;
    ADD LR9 LR9 {{ cr.out0_d3 }} ; DEC LR11 1 ;;
    BNE LR11 CR0 replica_y ;;
    // The first tile ends at the next output band's starting column.
    BNE LR4 {{ cr.w }} next_x ;;
    SET LR7 LR9 ;;
next_x:
    ADD LR8 LR8 LR6 ; ADD LR2 LR2 {{ cr.in0_d1 }} ; DEC LR4 1 ;;
    BNE LR2 {{ cr.pair_width }} x_ready ;;
    SET LR2 CR0 ; INC LR1 1 ;;
x_ready:
    BNE LR4 CR0 source_x ;;
    DEC LR3 1 ;;
    BNE LR3 CR0 source_y ;;
    DEC LR13 1 ;;
    BNE LR13 CR0 batch ;;
    HALT ;;
