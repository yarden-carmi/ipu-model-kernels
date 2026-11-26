{% macro span(dst, remaining, size, axis) %}
    SET {{ dst }} {{ cr.four }} ; BNE {{ remaining }} {{ size }} {{ axis }}_left_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_left_done:
    BNE {{ remaining }} CR1 {{ axis }}_right_done ;;
    INC {{ dst }} 1 ;;
{{ axis }}_right_done:
{% endmacro %}
    SET LR1 CR0 ; SET LR7 CR0 ; SET LR14 CR0 ;;
    SET LR13 {{ cr.in0_d0 }} ;;
batch:
    SET LR3 {{ cr.h }} ;;
source_y:
    {{ span('LR5', 'LR3', cr.h, 'y') }}
    SET LR4 {{ cr.w }} ; SET LR8 LR7 ; SET LR6 CR0 ;;
source_x:
    {{ span('LR6', 'LR4', cr.w, 'x') }}
    SET LR12 CR0 ;;
    MULT.EE LR12 CR0 0 LR12 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR15 LR1 ; SET LR2 CR0 ; ADD LR11 LR14 {{ cr.w }} ;;
    SUB LR11 LR11 LR4 ;;
channel:
    LD.MULT R0 LR15 {{ cr.in0 }} ;;
    MULT.EE LR11 CR1 0 LR12 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR2 {{ cr.one }}.L ;;
    ADD LR15 LR15 {{ cr.rowstep }} ; ADD LR11 LR11 {{ cr.lanestep }} ; INC LR2 1 ;;
    BLT.S LR11 LR0 channel_nowrap ;;
    SUB LR11 LR11 LR0 ; INC LR15 1 ;;
channel_nowrap:
    BNE LR2 {{ cr.in0_d1 }} channel ;;
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
    ADD LR8 LR8 LR6 ; DEC LR4 1 ;;
    BNE LR4 CR0 source_x ;;
    ADD LR14 LR14 {{ cr.w }} ;;
    BLT.S LR14 LR0 y_nowrap ;;
    SUB LR14 LR14 LR0 ; INC LR1 1 ;;
y_nowrap:
    DEC LR3 1 ;;
    BNE LR3 CR0 source_y ;;
    DEC LR13 1 ;;
    BNE LR13 CR0 batch ;;
    HALT ;;
