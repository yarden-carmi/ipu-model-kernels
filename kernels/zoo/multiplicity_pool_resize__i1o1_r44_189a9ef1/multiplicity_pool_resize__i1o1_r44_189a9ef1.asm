{# Each output lane accumulates at most four unique spatial taps. The 3:1
   multiplicities on each axis yield weights 9, 3, 3, 1 over 16. #}
{% macro store() %}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
INC LR8 1 ;;
{% endmacro %}

{% macro output(x, y, xy) %}
LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ;;
MULT.RC.VE LR0 {{ cr.center }} 0 LR0 {{ cr.ds_in }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC {{ x }} {{ cr.in0 }} LR0 ;;
MULT.RC.VE LR0 {{ cr.side }} 0 LR0 {{ cr.ds_in }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC {{ y }} {{ cr.in0 }} LR0 ;;
MULT.RC.VE LR0 {{ cr.side }} 0 LR0 {{ cr.ds_in }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC {{ xy }} {{ cr.in0 }} LR0 ;;
MULT.RC.VE LR0 {{ cr.corner }} 0 LR0 {{ cr.ds_in }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ store() }}
{% endmacro %}

{% macro row(phase) %}
ADD LR2 LR1 CR0 ;;
BEQ LR10 {{ 'CR0' if phase == 'even' else cr.last_y }} y_clamped_{{ phase }} ;;
{{ 'SUB' if phase == 'even' else 'ADD' }} LR2 LR1 {{ cr.w }} ;;
y_clamped_{{ phase }}:
ADD LR3 LR1 CR0 ; ADD LR4 LR2 CR0 ; SET LR9 CR0 ;;
x_loop_{{ phase }}:
ADD LR5 LR3 CR0 ; ADD LR6 LR4 CR0 ;;
BEQ LR9 CR0 left_clamped_{{ phase }} ;;
DEC LR5 1 ; DEC LR6 1 ;;
left_clamped_{{ phase }}:
{{ output('LR5', 'LR4', 'LR6') }}
ADD LR5 LR3 CR0 ; ADD LR6 LR4 CR0 ;;
BEQ LR9 {{ cr.last_x }} right_clamped_{{ phase }} ;;
INC LR5 1 ; INC LR6 1 ;;
right_clamped_{{ phase }}:
{{ output('LR5', 'LR4', 'LR6') }}
INC LR3 1 ; INC LR4 1 ; INC LR9 1 ; BLT.S LR9 {{ cr.last_x }} x_loop_{{ phase }} ;;
{% endmacro %}

{% if oh == in0_d2 and ow == in0_d3 %}
identity_loop:
LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ cr.ds_in }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ store() }}
INC LR9 1 ; BLT.S LR9 {{ cr.last_x }} identity_loop ;;
SET LR9 CR0 ; INC LR10 1 ; BLT.S LR10 {{ cr.last_y }} identity_loop ;;
SET LR10 CR0 ; INC LR11 1 ;;
BLT.S LR11 {{ cr.batches }} identity_loop ;;
{% else %}
batch_loop:
SET LR10 CR0 ;;
y_loop:
{{ row('even') }}
{{ row('odd') }}
ADD LR1 LR1 {{ cr.w }} ; INC LR10 1 ; BLT.S LR10 {{ cr.last_y }} y_loop ;;
INC LR11 1 ;;
BLT.S LR11 {{ cr.batches }} batch_loop ;;
{% endif %}
HALT ;;
