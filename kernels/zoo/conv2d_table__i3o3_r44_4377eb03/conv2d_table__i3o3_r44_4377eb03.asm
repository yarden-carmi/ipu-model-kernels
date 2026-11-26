{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.sizes ~ '.L' %}
{% set it = (in0_d3+127)//128 %}
{% set ot = (out0_d3+127)//128 %}
{% macro shape(tile) %}{{ cr.sizes }}.{{ 'H' if tile == ot-1 else 'L' }}{% endmacro %}
{% macro imm(r,n) %}
SET {{ r }} CR0 ;;
{% for j in range(n//128) %}INC {{ r }} 128 ;;{% endfor %}
{% if n%128 %}INC {{ r }} {{ n%128 }} ;;{% endif %}
{% endmacro %}

# Stage each input row once per horizontal tap. X padding is masked in
# the weights; the vertical padding is materialized in the stencil.
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ;;
DEC LR1 1 ; DEC LR2 1 ;;
{{ imm('LR6',128) }}
{{ imm('LR7',256) }}
{{ imm('LR8',384) }}
{{ imm('LR10',2) }}
{% macro guard(label) %}
{% if padding %}
{{ imm('LR5',padding*kw*ot-1) }}
SET LR4 CR0 ; MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{{ label }}:
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ; INC LR4 1 ; BLT.S LR4 LR5 {{ label }} ;;
{% endif %}
{% endmacro %}
stage_channel:
{{ guard('top') }}
SET LR4 CR0 ;;
stage_row:
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; INC LR1 1 ;;
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR6 ;;
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR7 ; {% if it == 2 %}INC LR1 1 ;{% endif %} ;;
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR8 ;;
{% macro stage(tile,kx) %}
{{ imm('LR9',128 + tile*128*stride + kx - padding) }}
{% if stride == 2 %}
MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
INC LR9 128 ;;
MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.STRIDE 64 on off LR10 ;
{% else %}
MULT.RC.VE LR9 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
{% endif %}
ACTIVATE.QUANTIZE identity {{ shape(tile) }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ;;
{% endmacro %}
{% for kx in range(kw) %}
{% for tile in range(ot) %}{{ stage(tile,kx) }}{% endfor %}
{% endfor %}
INC LR4 1 ; BLT.S LR4 {{ cr.ih_last }} stage_row ;;
{{ guard('bottom') }}
INC LR3 1 ; BLT.S LR3 LR11 stage_channel ;;

SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
SET LR4 CR0 ; SET LR11 CR0 ; SET LR15 CR0 ;;
DEC LR1 1 ; DEC LR2 1 ; DEC LR3 {{ ot }} ;;
{% for i in range(5) %}LD.LUT {{ i }} {{ cr.lut }} LR1 ; INC LR1 1 ;;{% endfor %}
output_channel:
{% macro product_rows() %}
LD.MULT R0 LR6 {{ cr.weights }} ; INC LR6 1 ;;
{% for part in range(3) %}
MULT.RC.VV LR0 R{{ part%2 }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% if part<2 %}LD.MULT R{{ (part+1)%2 }} LR6 {{ cr.weights }} ; INC LR6 1 ;{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro convolve(tile) %}
SET LR5 CR0 ; SET LR7 LR4 ; SET LR1 LR3 ;;
{% if tile %}INC LR7 {{ tile }} ; INC LR1 {{ tile }} ;;{% endif %}
output_row_{{ tile }}:
SET LR6 LR2 ; SET LR8 LR7 ; SET LR9 CR0 ;;
{# Bias uses R0 for all three residual pieces. #}
{% for part in range(3) %}
LD.MULT R0 LR6 {{ cr.weights }} ; INC LR6 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.{{ 'ADD.FIRST' if part == 0 else 'ADD' }} ;;
{% endfor %}
input_channel_{{ tile }}:
SET LR10 LR8 ;;
DEC LR10 {{ ot }} ;;
{% for tap in range(kh*kw) %}
LD.MULT.CYCLIC LR10 {{ cr.stencil }} LR0 ; INC LR10 {{ ot }} ;;
{{ product_rows() }}
{% endfor %}
ADD LR8 LR8 {{ cr.plane }} ; INC LR9 1 ; BLT.S LR9 LR13 input_channel_{{ tile }} ;;
ACTIVATE.QUANTIZE {{ 'generic' if act_out0 not in ['identity','relu','relu6'] else act_out0 }} {{ shape(tile) }} {{ qo }} {{ cr.out0 }} LR1 ; INC LR1 {{ ot }} ; INC LR7 {{ stride*kw*ot }} ; INC LR5 1 ; BLT.S LR5 {{ cr.oh_last }} output_row_{{ tile }} ;;
SET LR2 LR6 ;;
{% endmacro %}
{% for tile in range(ot) %}{{ convolve(tile) }}{% endfor %}
ADD LR3 LR3 {{ cr.output_plane }} ; INC LR15 1 ; BLT.S LR15 LR14 same_group ;;
ADD LR4 LR4 {{ cr.group_plane }} ; SET LR15 CR0 ;;
same_group:
INC LR11 1 ; BLT.S LR11 LR12 output_channel ;;
HALT ;;
