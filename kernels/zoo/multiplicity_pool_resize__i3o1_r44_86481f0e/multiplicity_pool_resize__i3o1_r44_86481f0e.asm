{# Accumulate four scalar taps into each channel lane. #}
{% macro pixel(tag) %}
ADD LR9 LR3 LR5 ; ADD LR10 LR4 LR5 ; ADD LR11 LR3 LR6 ;;
ADD LR12 LR4 LR6 ;;
SET LR7 LR1 ; SET LR8 LR2 ; SET LR14 CR0 ;;
MULT.EE LR0 CR0 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
channel_{{ tag }}:
LD.MULT R0 LR7 {{ cr.in0 }} ;;
MULT.EE LR9 {{ cr.center }} 0 LR0 {{ cr.ds_one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.ds_one }}.L ;;
MULT.EE LR11 {{ cr.side }} 0 LR0 {{ cr.ds_one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.ds_one }}.L ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
MULT.EE LR10 {{ cr.side }} 0 LR0 {{ cr.ds_one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.ds_one }}.L ;;
MULT.EE LR12 {{ cr.corner }} 0 LR0 {{ cr.ds_one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.ds_one }}.L ;;
BEQ LR14 {{ cr.last_channel }} channel_done_{{ tag }} ;;
ADD LR7 LR7 {{ cr.channel_stride }} ; ADD LR8 LR8 {{ cr.channel_stride }} ; INC LR14 1 ; BEQ CR0 CR0 channel_{{ tag }} ;;
channel_done_{{ tag }}:
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
INC LR13 1 ;;
{% endmacro %}

{% macro row(phase) %}
SET LR2 LR1 ; SET LR4 LR3 ;;
BEQ LR15 {{ 'CR0' if phase == 'even' else cr.last_y }} y_done_{{ phase }} ;;
{% if phase == 'even' %}
BEQ LR3 CR0 y_prev_row_{{ phase }} ;;
SET LR4 CR0 ; BEQ CR0 CR0 y_done_{{ phase }} ;;
y_prev_row_{{ phase }}:
DEC LR2 1 ; INC LR4 {{ in0_d3 }} ;;
{% else %}
BEQ LR3 CR0 y_same_row_{{ phase }} ;;
INC LR2 1 ; SET LR4 CR0 ; BEQ CR0 CR0 y_done_{{ phase }} ;;
y_same_row_{{ phase }}:
INC LR4 {{ in0_d3 }} ;;
{% endif %}
y_done_{{ phase }}:
SET LR5 CR0 ;;
x_loop_{{ phase }}:
SET LR6 LR5 ; BEQ LR5 CR0 x_left_{{ phase }} ;;
DEC LR6 1 ;;
x_left_{{ phase }}:
{{ pixel(phase ~ '_left') }}
SET LR6 LR5 ; BEQ LR5 {{ cr.last_x }} x_right_{{ phase }} ;;
INC LR6 1 ;;
x_right_{{ phase }}:
{{ pixel(phase ~ '_right') }}
BEQ LR5 {{ cr.last_x }} x_done_{{ phase }} ;;
INC LR5 1 ; BEQ CR0 CR0 x_loop_{{ phase }} ;;
x_done_{{ phase }}:
{% endmacro %}

SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
SET LR13 CR0 ; SET LR15 CR0 ;;
y_loop:
{{ row('even') }}
{{ row('odd') }}
BEQ LR3 CR0 y_first_half ;;
SET LR3 CR0 ; INC LR1 1 ; BEQ CR0 CR0 y_next ;;
y_first_half:
INC LR3 {{ in0_d3 }} ;;
y_next:
BEQ LR15 {{ cr.last_y }} finished ;;
INC LR15 1 ; BEQ CR0 CR0 y_loop ;;
finished:
HALT ;;
