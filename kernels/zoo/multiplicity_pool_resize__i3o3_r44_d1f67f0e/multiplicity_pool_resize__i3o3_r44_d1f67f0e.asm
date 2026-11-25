{% macro mul(weight) %}MULT.RC.VE LR0 {{ weight }} 0 LR0 {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L{% endmacro %}
{% macro reshape() %}{{ mul(cr.route_scale) }} ; ACC.RESHAPE LRD4 LRD6 0{% endmacro %}

{# Route one packed half to a full-width vector. Center and side are
   stored consecutively, in the input format, without any pooling yet. #}
{% macro route(kind, half) %}
SET LR6 LR10 ; SET LR7 LR10 ; SET LR4 {{ cr.center_lo if kind == 'center' else cr.side_lo }} ;;
ADDBI LRD6 4 ; SET LR5 {{ cr.center_hi if kind == 'center' else cr.side_hi }} ;;
SET LR6 LR10{% if half %} ; ADDBI LRD4 {{ in0_d3 }}{% endif %} ;;
{% for group in range(16) %}
{% if kind == 'side' and group == 1 %}
SUB LR4 LR4 CR1 ;;
{% elif kind == 'side' and group == 15 %}
SUB LR5 LR5 LR15 ;;
{% endif %}
{{ reshape() }}{% if group == 15 %} ; ACTIVATE.QUANTIZE identity {{ cr.ds_full }}.L {{ cr.qf_in0 }}.L {{ cr.routed }} LR2{% endif %} ;;
{% if group < 15 %}
ADDBI LRD4 4 ; ADDBI LRD6 8 ;;
{% endif %}
{% endfor %}
INC LR2 1 ;;
{% endmacro %}

pack_loop:
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
{% for half in range(2) %}
{{ route('center', half) }}
{{ route('side', half) }}
{% endfor %}
INC LR1 1 ;;
BNE LR1 LR12 pack_loop ;;

{% macro load(ptr) %}LD.MULT.CYCLIC {{ ptr }} {{ cr.routed }} LR0{% endmacro %}
{% macro output(phase) %}
SET LR5 LR3 ; BEQ LR4 {{ 'CR0' if phase == 'even' else 'LR14' }} clamp_{{ phase }} ;;
{{ 'DEC' if phase == 'even' else 'INC' }} LR5 2 ;;
clamp_{{ phase }}:
SET LR6 LR3 ; SET LR7 LR5 ; {{ load('LR3') }} ;;
INC LR6 1 ; INC LR7 1 ;;
{{ mul(cr.center) }} ; ACC.ADD.FIRST ; {{ load('LR6') }} ;;
{{ mul(cr.side) }} ; ACC.ADD ; {{ load('LR5') }} ;;
{{ mul(cr.side) }} ; ACC.ADD ; {{ load('LR7') }} ;;
{{ mul(cr.corner) }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
INC LR8 1 ;;
{% endmacro %}

plane_loop:
SET LR4 CR0 ;;
y_loop:
{{ output('even') }}
{{ output('odd') }}
INC LR3 2 ; INC LR4 1 ; BLT.S LR4 LR14 y_loop ;;
INC LR9 1 ;;
BLT.S LR9 LR13 plane_loop ;;
HALT ;;
