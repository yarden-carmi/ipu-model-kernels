{% set qi = cr.qf_in0 ~ '.L' %}
{% set qs = qi %}
{% set ds = cr.full ~ '.L' %}
{% set oh = out0_d2 %}
{% set ow = out0_d3 %}
{% set capacity = [ow, 128 // oh]|min %}
{% set candidate = ow // ((ow + capacity - 1) // capacity) %}
{% set pack = candidate if ow % candidate == 0 else 1 %}
{% macro weight() %}LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1{% endmacro %}

{# Width-lane convolution. Shift the cyclic input by one for the side taps;
   folded zero lanes suppress wraparound at both horizontal boundaries. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR4 CR0 ; SET LR10 CR0 ;;
SET LR12 CR0 ;;
INC LR1 128 ; INC LR10 127 ; INC LR12 129 ;;
conv_channel:
SET LR13 CR0 ;;
conv_batch:
SET LR7 CR0 ;;
conv_row:
SET LR5 LR4 ;;
DEC LR5 1 ;;
{{ weight() }} ;;
{% for part in range(3) %}
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if part == 0 else 'ACC.ADD' }} {% if part < 2 %}; {{ weight() }}{% endif %} ;;
{% endfor %}
SET LR6 LR7 ; SET LR8 LR2 ; SET LR9 LR7 ;;
DEC LR6 1 ; DEC LR8 1 ; INC LR9 2 ;;
conv_tap_row:
BLT.S LR6 CR0 skip_taps ;;
BGE.S LR6 {{ cr.in0_d2 }} skip_taps ;;
LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR1 ;;
{{ weight() }} ;;
{% for offset in ['LR10', 'LR1', 'LR12'] %}
{% for part in range(3) %}
MULT.RC.VV {{ offset }} R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD {% if offset != 'LR12' or part < 2 %}; {{ weight() }}{% endif %} ;;
{% endfor %}
{% endfor %}
B next_tap ;;
skip_taps:
INC LR5 9 ;;
next_tap:
INC LR6 1 ; INC LR8 1 ;;
BLT.S LR6 LR9 conv_tap_row ;;

{# Preserve a residual so transpose does not round to a horizontal row grid. #}
ACTIVATE.QUANTIZE identity {{ cr.wide }}.L {{ qs }} {{ cr.high }} LR3 ;;
LD.MULT R0 LR3 {{ cr.high }} ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qs }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ cr.wide }}.L {{ qs }} {{ cr.low }} LR3 ;;
INC LR3 1 ; INC LR2 {{ stride }} ; INC LR7 {{ stride }} ;;
BLT.S LR7 {{ cr.in0_d2 }} conv_row ;;
{% if stride == 2 and in0_d2 % 2 %}
DEC LR2 1 ;;
{% endif %}
INC LR13 1 ;;
BLT.S LR13 {{ cr.out0_d0 }} conv_batch ;;
INC LR4 30 ;;
BLT.S LR4 LR14 conv_channel ;;

{# The last two constant rows form a movable one-hot scatter vector.
   Traverse columns in packed groups, reconstructing each result in ACC. #}
LD.MULT.CYCLIC LR14 {{ cr.weights }} LR0 ;;
INC LR14 1 ; LD.MULT.CYCLIC LR14 {{ cr.weights }} LR1 ;;
SET LR3 CR0 ; SET LR11 CR0 ; SET LR14 CR0 ;;
SET LR15 CR0 ;;
{% if cout > 255 %}INC LR11 255 ;;{% endif %}
INC LR11 {{ cout if cout <= 255 else cout - 255 }} ;;
transpose_batch:
SET LR4 LR14 ; SET LR13 CR0 ;;
transpose_channel:
SET LR5 CR0 ; SET LR10 LR1 ; SET LR9 CR0 ;;
INC LR9 {{ ow * stride }} ;;
transpose_group:
SET LR6 LR1 ; SET LR8 LR5 ;;
INC LR8 {{ pack * stride }} ;;
MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qs }} ; ACC.ADD.FIRST ;;
transpose_column:
SET LR2 LR4 ; SET LR7 LR4 ;;
INC LR7 {{ oh }} ;;
transpose_lane:
LD.MULT R0 LR2 {{ cr.high }} ;;
MULT.RC.VE LR6 LR5 0 LR0 {{ ds }} {{ qs }} ; ACC.ADD ; LD.MULT R1 LR2 {{ cr.low }} ;;
MULT.RC.VE LR6 LR10 0 LR0 {{ ds }} {{ qs }} ; ACC.ADD ;;
DEC LR6 1 ; INC LR2 1 ;;
BLT.S LR2 LR7 transpose_lane ;;
INC LR5 {{ stride }} ; INC LR10 {{ stride }} ;;
BLT.S LR5 LR8 transpose_column ;;
ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.packed }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR3 1 ;;
BLT.S LR5 LR9 transpose_group ;;
ADD LR4 LR4 {{ cr.plane_step }} ; INC LR13 1 ;;
BLT.S LR13 LR11 transpose_channel ;;
INC LR14 {{ oh }} ; INC LR15 1 ;;
BLT.S LR15 {{ cr.out0_d0 }} transpose_batch ;;
HALT ;;
