{% macro load(ptr) %}LD.MULT.CYCLIC {{ ptr }} {{ cr.in0 }} LR0{% endmacro %}
{% macro mul(weight) %}MULT.RC.VE LR0 {{ weight }} 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L{% endmacro %}
{% macro output(x, xy) %}
{{ load('LR3') }} ;;
{{ mul(cr.center) }} ; ACC.ADD.FIRST ; {{ load(x) }} ;;
{{ mul(cr.side) }} ; ACC.ADD ; {{ load('LR4') }} ;;
{{ mul(cr.side) }} ; ACC.ADD ; {{ load(xy) }} ;;
{{ mul(cr.corner) }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
INC LR8 1 ;;
{% endmacro %}

{% macro row(phase) %}
ADD LR2 LR1 CR0 ;;
BEQ LR10 {{ 'CR0' if phase == 'even' else cr.last_y }} y_clamped_{{ phase }} ;;
{{ 'SUB' if phase == 'even' else 'ADD' }} LR2 LR1 {{ cr.w }} ;;
y_clamped_{{ phase }}:
ADD LR3 LR1 CR0 ; ADD LR4 LR2 CR0 ; SET LR9 CR0 ;;
x_loop_{{ phase }}:
BEQ LR9 CR0 left_clamped_{{ phase }} ;;
ADD LR5 LR3 CR0 ; ADD LR6 LR4 CR0 ;;
DEC LR5 1 ; DEC LR6 1 ;;
{{ output('LR5', 'LR6') }}
BEQ CR0 CR0 left_done_{{ phase }} ;;
left_clamped_{{ phase }}:
{{ output('LR3', 'LR4') }}
left_done_{{ phase }}:
BEQ LR9 {{ cr.last_x }} right_clamped_{{ phase }} ;;
ADD LR5 LR3 CR0 ; ADD LR6 LR4 CR0 ;;
INC LR5 1 ; INC LR6 1 ;;
{{ output('LR5', 'LR6') }}
BEQ CR0 CR0 right_done_{{ phase }} ;;
right_clamped_{{ phase }}:
{{ output('LR3', 'LR4') }}
right_done_{{ phase }}:
INC LR3 1 ; INC LR4 1 ; INC LR9 1 ; BLT.S LR9 {{ cr.last_x }} x_loop_{{ phase }} ;;
{% endmacro %}

batch_loop:
SET LR10 CR0 ;;
y_loop:
{{ row('even') }}
{{ row('odd') }}
ADD LR1 LR1 {{ cr.w }} ; INC LR10 1 ; BLT.S LR10 {{ cr.last_y }} y_loop ;;
INC LR11 1 ; BLT.S LR11 {{ cr.last_batch }} batch_loop ;;
HALT ;;
