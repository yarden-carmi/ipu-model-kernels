{% set ow = out0_d3 %}
{% set rem = ow % 8 %}
{% set chunks = (w + 127)//128 %}
{% set fit = [out0_d2,128//ow]|min %}
{% set pack = [fit if out0_d2%fit == 0 else 1, out0_d2//2 if out0_d2%2 == 0 and out0_d2 > fit and out0_d2*ow <= 256 else 1]|max %}
{% set blocks = out0_d2//pack %}
{% set taps = kh*kw %}
{% set gc = cin//groups %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.ds_pair ~ '.L' %}
{% set dv = cr.ds_pair ~ '.H' %}
{% macro inc(r,n) %}
{% if n > 0 %}INC {{ r }} {{ n }} ;{% elif n < 0 %}DEC {{ r }} {{ -n }} ;{% endif %}
{% endmacro %}
{% macro imm(r,n) %}
SET {{ r }} CR0 ;;
{% if n|abs <= 255 %}
{% if n %}{{ inc(r,n) }} ;;{% endif %}
{% else %}
{% for bit in range(30,-1,-1) if n >= 2**bit %}
{% if n >= 2**(bit+1) %}ADD {{ r }} {{ r }} {{ r }} ;;{% endif %}
{% if (n//(2**bit))%2 %}INC {{ r }} 1 ;;{% endif %}
{% endfor %}
{% endif %}
{% endmacro %}

{% if stride == 1 and w == out0_d3 and h == out0_d2 %}
# A shifted tap spans at most two packed input rows. The folded coefficient
# vectors assign disjoint destination lanes to the rows without requantization.
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR4 CR0 ; SET LR15 CR0 ;;
DEC LR2 1 ; DEC LR3 1 ;;
MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR0 ;;
{% for i in range(5) %}
LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
{% if not loop.last %}INC LR0 1 ;;{% endif %}
{% endfor %}
SET LR0 CR0 ;;
{{ imm('LR15',cout) }}
direct_channel:
SET LR5 CR0 ;;
direct_block:
SET LR6 LR1 ; SET LR7 CR0 ; SET LR8 LR2 ;;
{% for i in range(3) %}
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }} ;;
{% endfor %}
direct_input:
SET LR9 LR5 ; SET LR10 CR0 ; SET LR12 CR0 ;;
{% set start = -padding*(w+1) %}
{% if start %}
{{ inc('LR9', start//(w*pack)) }} {{ inc('LR10', start%(w*pack)) }} ;;
{% endif %}
direct_ky:
SET LR13 CR0 ;;
direct_tap:
BLT.S LR10 LR0 shift_back ;;
BGE.S LR10 {{ cr.src_hi }} shift_forward ;;
BEQ LR0 LR0 load_0 ;;
shift_back:
ADD LR10 LR10 {{ cr.src_hi }} ; DEC LR9 1 ;;
BLT.S LR10 LR0 shift_back ;;
BEQ LR0 LR0 load_0 ;;
shift_forward:
SUB LR10 LR10 {{ cr.src_hi }} ; INC LR9 1 ;;
BGE.S LR10 {{ cr.src_hi }} shift_forward ;;
{% macro direct_part(i) %}
load_{{ i }}:
{% if i == 1 %}
SET LR11 CR0 ; INC LR9 1 ;;
INC LR11 128 ;;
{% endif %}
{% set slot = 'LR0' if i == 0 else 'LR11' %}
BLT.S LR9 LR0 zero_{{ i }} ;;
BGE.S LR9 {{ cr.src_lo }} zero_{{ i }} ;;
ADD LR14 LR6 LR9 ; LD.MULT.CYCLIC LR14 {{ cr.in0 }} {{ slot }} ; BEQ LR0 LR0 weight_{{ i }} ;;
zero_{{ i }}:
LD.MULT.CYCLIC LR0 {{ cr.stencil }} {{ slot }} ;;
weight_{{ i }}:
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;
{% if i == 1 %}SUB LR11 LR11 {{ cr.src_hi }} ; DEC LR9 1 ;{% endif %} ;;
{% if i == 1 %}ADD LR11 LR11 LR10 ;;{% endif %}
{% for j in range(3) %}
MULT.RC.VV {{ 'LR10' if i == 0 else 'LR11' }} R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% if not loop.last %}LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;{% endif %} ;;
{% endfor %}
{% endmacro %}
{{ direct_part(0) }}
{{ direct_part(1) }}
INC LR10 1 ; INC LR13 1 ; SET LR14 CR0 ;;
INC LR14 {{ kw }} ;;
BLT.S LR13 LR14 direct_tap ;;
{{ inc('LR10', w-kw) }} INC LR12 1 ; SET LR14 CR0 ;;
INC LR14 {{ kh }} ;;
BLT.S LR12 LR14 direct_ky ;;
ADD LR6 LR6 {{ cr.src_lo }} ; INC LR7 1 ;;
BLT.S LR7 {{ cr.dst_lo }} direct_input ;;
ACTIVATE.QUANTIZE generic {{ dv }} {{ qo }} {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR5 1 ;;
BLT.S LR5 {{ cr.src_lo }} direct_block ;;
SET LR2 LR8 ; INC LR4 1 ; DEC LR15 1 ;;
BLT.S LR4 {{ cr.dst_hi }} direct_same_group ;;
SET LR4 CR0 ; SET LR1 LR6 ;;
direct_same_group:
BLT.S LR0 LR15 direct_channel ;;
HALT ;;
{% else %}
# Width-contiguous input rows occupy the middle of the cyclic register.
# Scatter each stencil tap into the exact packed output lane order.
SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
SET LR7 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
INC LR5 128 ; INC LR6 128 ; INC LR7 192 ;;
INC LR6 128 ; ADD LR7 LR7 LR7 ;;
MULT.VE LR4 CR0 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR4 ;;
LD.MULT.CYCLIC LR4 {{ cr.stencil }} LR4 ;;
LD.MULT.CYCLIC LR4 {{ cr.stencil }} LR7 ;;
{% if chunks == 1 %}LD.MULT.CYCLIC LR4 {{ cr.stencil }} LR6 ;;{% endif %}
SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;

stage_channel:
{{ imm('LR12',-padding) }}
stage_block:
SET LR13 LR12 ;;
stage_ky:
{% macro stage_x(x) %}
SET LR2 {{ cr.dst_lo }} ; SET LR3 {{ cr.dst_hi }} ; SET LR9 LR13 ;;
SET LR14 CR0 ;;
subrow_{{ x }}:
BLT.S LR9 LR4 zeros_{{ x }} ;;
BGE.S LR9 {{ cr.in0_d2 }} zeros_{{ x }} ;;
{% if chunks == 2 %}ADD LR8 LR9 LR9 ;;{% else %}SET LR8 LR9 ;;{% endif %}
ADD LR8 LR8 LR11 ;;
LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR5 ;;
{% if chunks == 2 %}INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR6 ;;{% endif %}
BEQ LR4 LR4 gather_{{ x }} ;;
zeros_{{ x }}:
LD.MULT.CYCLIC LR4 {{ cr.stencil }} LR5 ;;
{% if chunks == 2 %}LD.MULT.CYCLIC LR4 {{ cr.stencil }} LR6 ;;{% endif %}
gather_{{ x }}:
SET LR7 LR5 ; SET LR15 CR0 ;;
{% if x != padding or ow >= 8 %}{{ inc('LR7',x-padding) }} {{ inc('LR15',ow//8) }} ;;{% endif %}
{% if ow >= 8 %}
{% set repeat = ow//8 - (1 if rem else 0) %}
{% if repeat > 0 %}
{% if rem %}DEC LR15 1 ;;{% endif %}
gather8_{{ x }}:
MULT.RC.VE LR7 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
INC LR7 {{ 8*stride }} ; ADDBI LRD2 8 ; DEC LR15 1 ; BLT.S CR1 LR15 gather8_{{ x }} ;;
{% endif %}
{% if rem %}
MULT.RC.VE LR7 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
INC LR7 {{ rem*stride }} ; ADDBI LRD2 {{ rem }} ;;
{% endif %}
{% else %}
DEC LR7 {{ (8-rem)*stride }} ;;
{% endif %}
{% if rem %}
MULT.RC.VE LR7 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 {{ 8-rem }} ;;
ADDBI LRD2 {{ 8 if ow >= 8 else ow }} ;;
{% endif %}
INC LR9 {{ stride }} ; INC LR14 1 ;;
{% if pack > 1 %}
{{ imm('LR15',pack) }}
BLT.S LR14 LR15 subrow_{{ x }} ;;
{% endif %}
ACTIVATE.QUANTIZE identity {{ dv }} {{ qi }} {{ cr.stencil }} LR10 ; INC LR10 1 ;;
{% endmacro %}
{% for x in range(kw) %}{{ stage_x(x) }}{% endfor %}
INC LR13 1 ;;
SET LR15 LR12 ;;
INC LR15 {{ kh }} ;;
BLT.S LR13 LR15 stage_ky ;;
INC LR12 {{ stride*pack if stride*pack <= 255 else 255 }} ;;
{% if stride*pack > 255 %}INC LR12 1 ;;{% endif %}
{{ imm('LR15', blocks*stride*pack-padding) }}
BLT.S LR12 LR15 stage_block ;;
{{ imm('LR15',in0_d2*chunks) }}
ADD LR11 LR11 LR15 ;;
{{ imm('LR15',cin*in0_d2*chunks) }}
BLT.S LR11 LR15 stage_channel ;;

SET LR0 CR0 ; SET LR1 CR0 ;;
DEC LR1 1 ;;
{% for i in range(5) %}LD.LUT {{ i }} {{ cr.lut }} LR1 ; INC LR1 1 ;;{% endfor %}
SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
DEC LR2 1 ; DEC LR3 1 ;;
{{ imm('LR12',blocks*taps) }}
{{ imm('LR13',blocks) }}
{{ imm('LR14',gc) }}
{{ imm('LR15',cout) }}

# The stencil is shared by all output channels of a group.
output_channel:
SET LR7 LR4 ; SET LR8 CR0 ;;
output_block:
SET LR9 LR2 ; SET LR10 LR7 ; SET LR11 CR0 ;;
{% for i in range(3) %}
LD.MULT R0 LR9 {{ cr.weights }} ; INC LR9 1 ;;
MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }} ;;
{% endfor %}
input_channel:
SET LR5 CR0 ;;
tap:
LD.MULT.CYCLIC LR10 {{ cr.stencil }} LR0 ; INC LR10 1 ;;
LD.MULT R0 LR9 {{ cr.weights }} ; INC LR9 1 ;;
{% for i in range(3) %}
MULT.RC.VE LR0 LR0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{% if not loop.last %}LD.MULT R0 LR9 {{ cr.weights }} ; INC LR9 1 ;{% endif %} ;;
{% endfor %}
INC LR5 1 ;;
{{ imm('LR1',taps) }}
BLT.S LR5 LR1 tap ;;
ADD LR10 LR10 LR12 ; INC LR11 1 ;;
DEC LR10 {{ taps }} ; BLT.S LR11 LR14 input_channel ;;
ACTIVATE.QUANTIZE generic {{ dv }} {{ qo }} {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR7 {{ taps }} ; INC LR8 1 ;;
BLT.S LR8 LR13 output_block ;;
SET LR2 LR9 ; INC LR6 1 ;;
{{ imm('LR1',cout//groups) }}
BLT.S LR6 LR1 same_group ;;
SET LR6 CR0 ;;
{{ imm('LR1',gc*blocks*taps) }}
ADD LR4 LR4 LR1 ;;
same_group:
DEC LR15 1 ;;
BLT.S LR0 LR15 output_channel ;;
HALT ;;
{% endif %}
