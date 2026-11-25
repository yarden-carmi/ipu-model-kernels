{% macro mult(weight) %}MULT.RC.VE LR0 {{ weight }} 0 LR0 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L{% endmacro %}

{# Route eight destinations at a time. Each expanded row carries the
   same set of input values, scaled by two to protect tiny values. #}
{% macro expand(neighbor, target) %}
{{ mult('CR0') }} ; ACC.ADD.FIRST ;;
SET LR4 LR6 ; SET LR5 LR7 ;;
{% for tile in range(in0_d3 // 4) %}
{% if not neighbor and loop.first %}
SET LR2 LR8 ; SET LR3 LR9 ;;
{% elif neighbor and loop.first %}
SET LR2 LR10 ; SET LR3 LR11 ;;
{% elif neighbor and loop.last %}
SET LR2 LR14 ; SET LR3 LR15 ;;
{% elif neighbor and tile == 1 %}
SET LR2 LR12 ; SET LR3 LR13 ;;
{% else %}
ADDBI LRD2 4 ;;
{% endif %}
{{ mult(cr.expand_scale) }} ; ACC.RESHAPE LRD2 LRD4 0 ;;
{% if not loop.last %}
ADDBI LRD4 8 ;;
{% endif %}
{% endfor %}
ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L {{ target }} LR1 ;;
{% endmacro %}

expand_loop:
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
{{ expand(false, cr.center_rows) }}
{{ expand(true, cr.side_rows) }}
INC LR1 1 ;;
BLT.S LR1 {{ cr.rows }} expand_loop ;;
SET LR6 CR0 ; SET LR8 CR0 ;;

{% macro pool(phase, boundary, step) %}
SET LR2 LR6 ; BEQ LR7 {{ boundary }} clamped_{{ phase }} ;;
{{ step }} LR2 1 ;;
clamped_{{ phase }}:
LD.MULT.CYCLIC LR6 {{ cr.center_rows }} LR0 ;;
{{ mult(cr.center) }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR6 {{ cr.side_rows }} LR0 ;;
{{ mult(cr.side) }} ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.center_rows }} LR0 ;;
{{ mult(cr.side) }} ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.side_rows }} LR0 ;;
{{ mult(cr.corner) }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
INC LR8 1 ;;
{% endmacro %}

channel_loop:
SET LR7 CR0 ;;
y_loop:
{{ pool('even', 'CR0', 'DEC') }}
{{ pool('odd', cr.last_y, 'INC') }}
INC LR6 1 ; INC LR7 1 ; BLT.S LR7 {{ cr.last_y }} y_loop ;;
BLT.S LR6 {{ cr.rows }} channel_loop ;;
HALT ;;
