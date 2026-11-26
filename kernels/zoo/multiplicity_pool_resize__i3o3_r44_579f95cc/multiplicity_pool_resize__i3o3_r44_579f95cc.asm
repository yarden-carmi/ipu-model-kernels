{# Build center and clamped neighbor vectors in output-width lane order.
   Each scatter fills eight lanes; the neighbor's last lane is patched. #}
{% macro route(neighbor) %}
{% set seed = cr.src_neighbor if neighbor else cr.src_center %}
SET LR0 {{ seed }} ; SET LR1 {{ seed }} ; SET LR2 {{ cr.dst_seed }} ;;
ADDBI LRD0 2 ; SET LR3 {{ cr.dst_seed }} ;;
SET LR0 {{ seed }} ; ADDBI LRD2 4 ;;
SET LR2 {{ cr.dst_seed }} ;;
{% if neighbor %}
ADDBI LRD0 -4 ;;
{% endif %}
{% for block in range(in0_d3 // 4) %}
MULT.RC.VE LR15 {{ cr.route_scale }} 0 LR15 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0{% if loop.last and not neighbor %} ; ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L {{ cr.routed }} LR5{% endif %} ;;
{% if not loop.last %}
ADDBI LRD0 4 ; ADDBI LRD2 8 ;;
{% if neighbor and loop.first %}
DEC LR0 1 ;;
{% endif %}
{% endif %}
{% endfor %}
{% if neighbor %}
ADDBI LRD0 -1 ;;
MULT.RC.VE LR15 {{ cr.route_scale }} 0 LR15 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L {{ cr.routed }} LR5 ;;
{% endif %}
INC LR5 1 ;;
{% endmacro %}

route_loop:
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR15 ;;
{{ route(false) }}
{{ route(true) }}
INC LR4 1 ;;
BLT.S LR4 {{ cr.input_rows }} route_loop ;;

{% macro load(row) %}LD.MULT.CYCLIC {{ row }} {{ cr.routed }} LR15{% endmacro %}
{% macro weighted(weight) %}MULT.RC.VE LR15 {{ weight }} 0 LR15 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L{% endmacro %}
{% macro emit(direction) %}
SET LR6 LR13 ; SET LR8 LR13 ; BEQ LR7 {{ 'CR0' if direction == 'prev' else 'LR12' }} channel_{{ direction }} ;;
{{ 'DEC' if direction == 'prev' else 'INC' }} LR8 {{ 2 * in0_d1 }} ;;
channel_{{ direction }}:
SET LR9 LR6 ; SET LR10 LR8 ; {{ load('LR6') }} ;;
INC LR9 1 ; INC LR10 1 ;;
{{ weighted(cr.center) }} ; ACC.ADD.FIRST ; {{ load('LR9') }} ;;
{{ weighted(cr.side) }} ; ACC.ADD ; {{ load('LR8') }} ;;
{{ weighted(cr.side) }} ; ACC.ADD ; {{ load('LR10') }} ;;
{{ weighted(cr.corner) }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ; INC LR6 2 ; INC LR8 2 ;;
INC LR11 1 ; BLT.S LR6 LR14 channel_{{ direction }} ;;
{% endmacro %}

INC LR14 {{ 2 * in0_d1 }} ;;
batch_loop:
SET LR7 CR0 ;;
y_loop:
{{ emit('prev') }}
{{ emit('next') }}
INC LR13 {{ 2 * in0_d1 }} ; INC LR14 {{ 2 * in0_d1 }} ; BEQ LR7 LR12 batch_end ;;
INC LR7 1 ; BEQ CR0 CR0 y_loop ;;
batch_end:
BLT.S LR13 LR5 batch_loop ;;
HALT ;;
