{% macro pixel(tag) %}
ADD LR9 LR3 LR5 ; ADD LR10 LR4 LR5 ; ADD LR11 LR3 LR6 ;;
ADD LR12 LR4 LR6 ;;
LD.MULT R0 LR1 {{ cr.in0 }} ;;
MULT.EE LR9 {{ cr.center }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR11 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.EE LR10 {{ cr.side }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
MULT.EE LR12 {{ cr.corner }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR14 {{ cr.one }}.L ;;
INC LR14 1 ;;
{% endmacro %}
{% macro row(phase) %}
SET LR2 LR1 ; SET LR4 LR3 ;;
BEQ LR15 {{ 'CR0' if phase == 'even' else cr.last_y }} y_done_{{ phase }} ;;
{% if phase == 'even' %}
BEQ LR3 CR0 y_prev_{{ phase }} ;;
SET LR4 CR0 ; BEQ CR0 CR0 y_done_{{ phase }} ;;
y_prev_{{ phase }}:
DEC LR2 1 ; INC LR4 {{ in0_d3 }} ;;
{% else %}
BEQ LR3 CR0 y_same_{{ phase }} ;;
INC LR2 1 ; SET LR4 CR0 ; BEQ CR0 CR0 y_done_{{ phase }} ;;
y_same_{{ phase }}:
INC LR4 {{ in0_d3 }} ;;
{% endif %}
y_done_{{ phase }}:
SET LR5 CR0 ; SET LR14 CR0 ;;
MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
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
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
INC LR13 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
SET LR8 CR0 ;;
plane:
SET LR3 CR0 ; SET LR15 CR0 ;;
y_loop:
{{ row('even') }}
{{ row('odd') }}
BEQ LR3 CR0 y_first_half ;;
SET LR3 CR0 ; INC LR1 1 ; BEQ CR0 CR0 y_next ;;
y_first_half:
INC LR3 {{ in0_d3 }} ;;
y_next:
BEQ LR15 {{ cr.last_y }} y_finished ;;
INC LR15 1 ; BEQ CR0 CR0 y_loop ;;
y_finished:
MULT.EE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.zero }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
INC LR13 1 ;;
BEQ LR8 {{ cr.last_plane }} finished ;;
INC LR8 1 ; BEQ CR0 CR0 plane ;;
finished:
HALT ;;
