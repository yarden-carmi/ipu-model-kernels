{# Expand each packed spatial row into alternating center and neighbor taps. #}
{% macro scatter(mask=0) %}
MULT.RC.VE LR7 {{ cr.upscale }} 0 LR9 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 {{ mask }} ;;
{% endmacro %}

{% macro route(kind, lo, hi) %}
ADD LR0 {{ lo }} CR0 ; ADD LR1 {{ hi }} CR0 ; SET LR8 CR0 ;;
ADD LR2 LR14 CR0 ; ADD LR3 LR15 CR0 ;;
{% if kind == 'neighbor' %}
{{ scatter() }}
INC LR8 1 ;;
BGE.S LR8 LR6 route_done_{{ kind }} ;;
ADDBI LRD0 4 ; ADDBI LRD2 8 ;;
DEC LR0 1 ;;
{% endif %}
route_loop_{{ kind }}:
{{ scatter() }}
ADDBI LRD0 4 ; ADDBI LRD2 8 ; INC LR8 1 ;;
BLT.S LR8 LR6 route_loop_{{ kind }} ;;
route_done_{{ kind }}:
{% if kind == 'neighbor' %}
SET LR1 {{ cr.edge_src }} ; SET LR3 {{ cr.edge_dst }} ;;
{{ scatter(7) }}
{% endif %}
ACTIVATE.QUANTIZE identity {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L {{ cr.routed }} LR4 ;;
INC LR4 1 ;;
{% endmacro %}

prep:
LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR9 ;;
route_half:
{{ route('center', 'LR10', 'LR11') }}
{{ route('neighbor', 'LR12', 'LR13') }}
BEQ LR7 CR0 second_half ;;
SET LR7 CR0 ; INC LR5 1 ;;
BLT.S LR4 {{ cr.end }} prep ;;
BEQ CR0 CR0 resize_init ;;
second_half:
INC LR7 {{ in0_d3 }} ;;
BEQ CR0 CR0 route_half ;;

resize_init:
SET LR4 CR0 ; SET LR0 CR0 ; SET LR1 CR0 ;;
SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
SET LR11 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
INC LR1 128 ; INC LR13 {{ out0_d0 }} ;;
ADD LR2 LR1 LR1 ;;
ADD LR3 LR2 LR1 ;;

{% macro tap(slot, coeff, first=false) %}
MULT.RC.VE {{ slot }} {{ coeff }} 0 LR9 {{ cr.ds_out }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro emit(phase, boundary, step) %}
ADD LR5 LR4 CR0 ; BEQ LR8 {{ boundary }} clamped_{{ phase }} ;;
{{ step }} LR5 2 ;;
clamped_{{ phase }}:
ADD LR6 LR5 CR1 ;;
LD.MULT.CYCLIC LR5 {{ cr.routed }} LR2 ;;
LD.MULT.CYCLIC LR6 {{ cr.routed }} LR3 ;;
{{ tap('LR0', cr.center, true) }}
{{ tap('LR1', cr.side) }}
{{ tap('LR2', cr.side) }}
{{ tap('LR3', cr.corner) }}
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
INC LR7 {{ out0_d1 }} ;;
{% endmacro %}

{# Input planes run channel then batch. Output rows run batch, y, channel. #}
plane:
SET LR8 CR0 ; ADD LR7 LR12 CR0 ;;
resize_row:
ADD LR6 LR4 CR1 ;;
LD.MULT.CYCLIC LR4 {{ cr.routed }} LR0 ;;
LD.MULT.CYCLIC LR6 {{ cr.routed }} LR1 ;;
{{ emit('even', 'CR0', 'DEC') }}
{{ emit('odd', cr.last_y, 'INC') }}
INC LR4 2 ; BEQ LR8 {{ cr.last_y }} next_plane ;;
INC LR8 1 ; BEQ CR0 CR0 resize_row ;;
next_plane:
BGE.S LR4 {{ cr.end }} finished ;;
INC LR11 1 ; ADD LR12 LR7 CR0 ;;
BLT.S LR11 LR13 plane ;;
INC LR10 1 ; SET LR11 CR0 ;;
ADD LR12 LR10 CR0 ; BEQ CR0 CR0 plane ;;
finished:
HALT ;;
