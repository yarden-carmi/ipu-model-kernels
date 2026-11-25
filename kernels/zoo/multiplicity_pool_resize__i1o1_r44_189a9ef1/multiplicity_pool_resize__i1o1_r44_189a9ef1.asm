{% macro load(ptr) %}LD.MULT.CYCLIC {{ ptr }} {{ cr.in0 }} LR0{% endmacro %}
{% macro mul(weight) %}MULT.RC.VE LR0 {{ weight }} 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L{% endmacro %}
{% macro store() %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8{% endmacro %}

{% macro output() %}
{{ load('LR3') }} ;;
{{ mul(cr.center) }} ; ACC.ADD.FIRST ; {{ load('LR5') }} ;;
{{ mul(cr.side) }} ; ACC.ADD ; {{ load('LR4') }} ;;
{{ mul(cr.side) }} ; ACC.ADD ; {{ load('LR6') }} ;;
{{ mul(cr.corner) }} ; ACC.ADD ; {{ store() }} ;;
INC LR8 1 ;;
{% endmacro %}

{# The 3:1 multiplicities on each axis give weights 9,3,3,1 over 16. #}
{% macro row(phase) %}
SET LR2 LR1 ; BEQ LR10 {{ 'CR0' if phase == 'even' else cr.last_y }} y_clamped_{{ phase }} ;;
{{ 'SUB' if phase == 'even' else 'ADD' }} LR2 LR1 {{ cr.w }} ;;
y_clamped_{{ phase }}:
SET LR3 LR1 ; SET LR4 LR2 ; SET LR9 CR0 ;;
x_loop_{{ phase }}:
{% for side in ['left', 'right'] %}
SET LR5 LR3 ; SET LR6 LR4 ; BEQ LR9 {{ 'CR0' if side == 'left' else cr.last_x }} {{ side }}_clamped_{{ phase }} ;;
{{ 'DEC' if side == 'left' else 'INC' }} LR5 1 ; {{ 'DEC' if side == 'left' else 'INC' }} LR6 1 ;;
{{ side }}_clamped_{{ phase }}:
{{ output() }}
{% endfor %}
INC LR3 1 ; INC LR4 1 ; INC LR9 1 ; BLT.S LR9 {{ cr.last_x }} x_loop_{{ phase }} ;;
{% endmacro %}

{% if in0_d2 == oh and in0_d3 == ow %}
copy_loop:
{{ load('LR8') }} ;;
{{ mul('CR1') }} ; ACC.ADD.FIRST ; {{ store() }} ;;
INC LR8 1 ;;
BLT.S LR8 {{ cr.last_row }} copy_loop ;;
{% else %}
batch_loop:
SET LR10 CR0 ;;
y_loop:
{{ row('even') }}
{{ row('odd') }}
ADD LR1 LR1 {{ cr.w }} ; INC LR10 1 ; BLT.S LR10 {{ cr.last_y }} y_loop ;;
INC LR11 1 ;;
BLT.S LR11 {{ cr.last_batch }} batch_loop ;;
{% endif %}
HALT ;;
