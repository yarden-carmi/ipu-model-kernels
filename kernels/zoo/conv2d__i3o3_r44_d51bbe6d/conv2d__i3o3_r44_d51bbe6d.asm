{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}
{% set tail = taps % 128 %}

{% macro cursor(row, lane, delta, tag) %}
 SET {{row}} CR0 ; SET LR4 LR5 ; SET {{lane}} LR13 ;;
 {% if delta %}INC LR4 {{delta}} ;;{% endif %}
 BLT.S LR4 CR0 invalid_{{tag}} ;;
 BGE.S LR4 {{cr.in0_d2}} invalid_{{tag}} ;;
 div_{{tag}}:
 DEC LR4 {{pack}} ;;
 BLT.S LR4 CR0 rem_{{tag}} ;;
 INC {{row}} 1 ; B div_{{tag}} ;;
 rem_{{tag}}:
 INC LR4 {{pack}} ;;
 BEQ LR4 CR0 ready_{{tag}} ;;
 lane_{{tag}}:
 INC {{lane}} {{in0_d3}} ; DEC LR4 1 ;;
 BNE LR4 CR0 lane_{{tag}} ;;
 B ready_{{tag}} ;;
 invalid_{{tag}}:
 DEC {{row}} 1 ;;
 ready_{{tag}}:
{% endmacro %}

{% macro quad_patch(kx) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
 {% for half in range(4) %}
 {{cursor('LR14', 'LR8', half, 'quad_' ~ kx ~ '_' ~ half)}}
 SET LR4 CR0 ;;
 INC LR4 {{kx + 1 + 3 * half}} ;;
 LD.MULT R0 LR4 {{cr.masks}} ;;
 BLT.S LR14 CR0 quad_skip_{{kx}}_{{half}} ;;
 ADD LR14 LR14 LR7 ;;
 LD.MULT.CYCLIC LR14 {{cr.in0}} LR13 ;;
 {% set dx = kx - padding - half * out0_d3 %}
 {% if dx %}{{'INC' if dx > 0 else 'DEC'}} LR8 {{dx | abs}} ;;{% endif %}
 MULT.RC.VV LR8 R0 0 LR0 {{full}} {{qi}} ; ACC.ADD ;;
 quad_skip_{{kx}}_{{half}}:
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro pair_half(kx, half) %}
 {% set row = 'LR7' if half == 0 else 'LR14' %}
 {% set lane = 'LR8' if half == 0 else 'LR12' %}
 SET LR4 CR0 ; SET LR11 {{lane}} ;;
 INC LR4 {{kx + 1 + 3 * half}} ;;
 LD.MULT R0 LR4 {{cr.masks}} ;;
 BLT.S {{row}} CR0 skip_{{kx}}_{{half}} ;;
 LD.MULT.CYCLIC {{row}} {{cr.in0}} LR13 ;;
 {% set dx = kx - padding - half * out0_d3 %}
 {% if dx %}{{'INC' if dx > 0 else 'DEC'}} LR11 {{dx | abs}} ;;{% endif %}
 MULT.RC.VV LR11 R0 0 LR0 {{full}} {{qi}} ; ACC.ADD ;;
 skip_{{kx}}_{{half}}:
{% endmacro %}

{% macro pair_patch(kx) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
 {{pair_half(kx, 0)}}
 {{pair_half(kx, 1)}}
 ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro patch(kx) %}
 SET LR11 LR8 ; SET LR12 CR0 ;;
 INC LR12 {{kx + 1}} ;;
 {% set dx = kx - padding %}
 {% if dx %}{{'INC' if dx > 0 else 'DEC'}} LR11 {{dx | abs}} ;;{% endif %}
 LD.MULT R0 LR12 {{cr.masks}} ;;
 {% if stride == 2 %}
 MULT.RC.VV LR11 R0 0 LR0 {{full}} {{qi}} ; ACC.STRIDE 64 on off LR0 ;;
 {% else %}
 MULT.RC.VV LR11 R0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
 {% endif %}
 ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro reduce_panel(count, tag, limit) %}
 LD.MULT R0 LR6 {{cr.weights}} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{cr.patches}} LR13 ; INC LR6 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{tag}}:
 MULT.RC.VE LR13 LR7 0 LR0 {{full}} {{qi}} ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{cr.patches}} LR13 ; INC LR7 1 ; INC LR4 1 ; BLT.S LR7 {{limit}} mac_{{tag}} ;;
 {% endif %}
 MULT.RC.VE LR13 LR7 0 LR0 {{full}} {{qi}} ; ACC.ADD ; INC LR7 1 ; INC LR4 1 ;;
{% endmacro %}

SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
SET LR13 CR0 ; SET LR9 CR0 ;;
INC LR13 128 ;;
{% if padding %}DEC LR3 {{padding}} ;;{% endif %}
{% if tail > 3 %}INC LR9 {{tail - 3}} ;;{% elif tail == 2 %}DEC LR9 1 ;;{% endif %}
spatial_row:
LD.MULT.CYCLIC LR0 {{cr.masks}} LR0 ; SET LR1 CR0 ; SET LR5 LR3 ;;
ky:
{% if out_pack == 4 %}
SET LR7 CR0 ; SET LR10 CR0 ;;
quad_channel:
{% for kx in range(3) %}{{quad_patch(kx)}}{% endfor %}
INC LR10 1 ; ADD LR7 LR7 {{cr.channel_rows}} ;;
BLT.S LR10 {{cr.in0_d1}} quad_channel ;;
{% elif out_pack == 2 %}
{{cursor('LR7', 'LR8', 0, 'first')}}
{{cursor('LR14', 'LR12', 1, 'second')}}
SET LR10 CR0 ;;
paired_channel:
{% for kx in range(3) %}{{pair_patch(kx)}}{% endfor %}
BLT.S LR7 CR0 keep_first ;;
ADD LR7 LR7 {{cr.channel_rows}} ;;
keep_first:
BLT.S LR14 CR0 keep_second ;;
ADD LR14 LR14 {{cr.channel_rows}} ;;
keep_second:
INC LR10 1 ;;
BLT.S LR10 {{cr.in0_d1}} paired_channel ;;
{% else %}
BLT.S LR5 CR0 zero_ky ;;
BGE.S LR5 {{cr.in0_d2}} zero_ky ;;
SET LR7 CR0 ; SET LR14 LR5 ; SET LR8 LR13 ;;
{# Divide y by the input pack to find its XMEM row and cyclic lane base. #}
packed_y:
DEC LR14 {{pack}} ;;
BLT.S LR14 CR0 packed_remainder ;;
INC LR7 1 ; B packed_y ;;
packed_remainder:
INC LR14 {{pack}} ;;
BEQ LR14 CR0 source_ready ;;
lane_base:
INC LR8 {{in0_d3}} ; DEC LR14 1 ;;
BNE LR14 CR0 lane_base ;;
source_ready:
SET LR10 CR0 ;;
channel:
LD.MULT.CYCLIC LR7 {{cr.in0}} LR13 ;;
{% for kx in range(3) %}{{patch(kx)}}{% endfor %}
INC LR10 1 ; ADD LR7 LR7 {{cr.channel_rows}} ;;
BLT.S LR10 {{cr.in0_d1}} channel ;;
B next_ky ;;
zero_ky:
SET LR10 CR0 ; SET LR12 {{cr.in0_d1}} ;;
ADD LR12 LR12 {{cr.in0_d1}} ;;
ADD LR12 LR12 {{cr.in0_d1}} ;;
MULT.RC.VE LR0 CR0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
zero_patch:
ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
INC LR1 1 ; INC LR10 1 ;;
BLT.S LR10 LR12 zero_patch ;;
{% endif %}
next_ky:
INC LR5 1 ; SET LR14 LR3 ;;
INC LR14 3 ;;
BLT.S LR5 LR14 ky ;;

SET LR6 CR0 ; SET LR8 CR0 ; SET LR11 LR2 ;;
INC LR8 125 ;;
output_channel:
LD.MULT.CYCLIC LR6 {{cr.weights}} LR0 ; SET LR12 CR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ; INC LR6 1 ;;
SET LR4 CR0 ; SET LR10 CR0 ;;
{% if taps // 128 %}
panel:
{{reduce_panel(128, 'full', 'LR8')}}
INC LR10 1 ;;
{% if tail %}
SET LR14 LR15 ;;
DEC LR14 1 ;;
BLT.S LR10 LR14 panel ;;
{% else %}
BLT.S LR10 LR15 panel ;;
{% endif %}
{% endif %}
{% if tail %}{{reduce_panel(tail, 'tail', 'LR9')}}{% endif %}
{% macro write_out(ds) %}
ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}} {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
{% endmacro %}
{% if out0_d2 % out_pack %}
SET LR14 LR3 ;;
INC LR14 {{out_pack - 1}} ;;
BLT.S LR14 {{cr.yend}}.L store_pair ;;
{{write_out(cr.width ~ '.H')}}
B stored ;;
store_pair:
{% endif %}
{{write_out(width)}}
stored:
ADD LR2 LR2 {{cr.yend}}.H ;;
BLT.S LR6 {{cr.weight_rows}} output_channel ;;
SET LR2 LR11 ; INC LR3 {{stride * out_pack}} ;;
INC LR2 1 ;;
BLT.S LR3 {{cr.yend}}.L spatial_row ;;
HALT ;;
