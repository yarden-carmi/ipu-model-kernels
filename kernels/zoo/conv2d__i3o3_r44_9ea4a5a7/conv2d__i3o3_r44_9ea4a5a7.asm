{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set width = cr.width ~ '.L' %}

{# Build one tap vector spanning both output lines. For stride two, place
   the two segments before decimation, at twice their final lane offsets. #}
{% macro half_patch(kx, half, acc) %}
 {% set row = 'LR7' if half == 0 else 'LR14' %}
 SET LR4 CR0 ; SET LR8 LR13 ;;
 INC LR4 {{1 + kx + kw * half}} ;;
 LD.MULT R0 LR4 {{cr.masks}} ;;
 BLT.S {{row}} CR0 skip_{{kx}}_{{half}} ;;
 LD.MULT.CYCLIC {{row}} {{cr.in0}} LR13 ;;
 {% set dx = kx - padding - half * out0_d3 * stride %}
 {% if dx %}{{'INC' if dx > 0 else 'DEC'}} LR8 {{dx | abs}} ;;{% endif %}
 MULT.RC.VV LR8 R0 0 LR0 {{full}} {{qi}} ; {{acc}} ;;
 skip_{{kx}}_{{half}}:
{% endmacro %}

{% macro patch(kx) %}
 {% if stride == 1 %}
 MULT.RC.VE LR0 CR0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
 {{half_patch(kx, 0, 'ACC.ADD')}}
 {{half_patch(kx, 1, 'ACC.ADD')}}
 {% else %}
 {# Decimate each disjoint segment, then sum the two patch rows in the MAC. #}
 {{strided_patch(kx, 0)}}
 {{strided_patch(kx, 1)}}
 {% endif %}
 {% if stride == 1 %}
 {{store_patch()}}
 {% endif %}
{% endmacro %}

{% macro strided_patch(kx, half) %}
 MULT.RC.VE LR0 CR0 0 LR0 {{full}} {{qi}} ; ACC.ADD.FIRST ;;
 {{half_patch(kx, half, 'ACC.STRIDE 64 on off LR0')}}
 {{store_patch()}}
{% endmacro %}

{% macro store_patch() %}
 ACTIVATE.QUANTIZE identity {{width}} {{qi}} {{cr.patches}} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

{% macro mac(load) %}
 MULT.RC.VE LR13 LR7 0 LR0 {{full}} {{qi}} ; ACC.ADD ; {% if load %} LD.MULT.CYCLIC LR4 {{cr.patches}} LR13 ; {% endif %} INC LR7 1 ; INC LR4 1
{% endmacro %}

{% macro reduce_panel(count, tag, limit) %}
 LD.MULT R0 LR6 {{cr.weights}} ; SET LR7 CR0 ;;
 LD.MULT.CYCLIC LR4 {{cr.patches}} LR13 ; INC LR6 1 ; DEC LR7 1 ;;
 {% if count > 1 %}
 mac_{{tag}}:
 {{mac(true)}} ; BLT.S LR7 {{limit}} mac_{{tag}} ;;
 {% endif %}
 {{mac(false)}} ;;
{% endmacro %}

SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
SET LR13 CR0 ; SET LR9 CR0 ;;
INC LR13 128 ;;
DEC LR3 {{padding}} ;;
{% set rt = taps % 128 %}
{% if rt > 3 %}INC LR9 {{rt - 3}} ;;{% elif rt == 2 %}DEC LR9 1 ;;{% endif %}
spatial_row:
LD.MULT.CYCLIC LR0 {{cr.masks}} LR0 ; SET LR1 CR0 ; SET LR5 LR3 ;;
ky:
SET LR7 LR5 ; SET LR14 LR5 ;;
INC LR14 {{stride}} ;;
{% macro validate(row, tag) %}
 BLT.S {{row}} CR0 invalid_{{tag}} ;;
 BLT.S {{row}} {{cr.in0_d2}} valid_{{tag}} ;;
 invalid_{{tag}}:
 SET {{row}} CR0 ;;
 DEC {{row}} 1 ;;
 valid_{{tag}}:
{% endmacro %}
{{validate('LR7', 'first')}}
{{validate('LR14', 'second')}}
SET LR10 CR0 ;;
patch_channel:
{% for kx in range(kw) %}{{patch(kx)}}{% endfor %}
{% macro advance(row, tag) %}
 BLT.S {{row}} CR0 keep_{{tag}} ;;
 ADD {{row}} {{row}} {{cr.in0_d2}} ;;
 keep_{{tag}}:
{% endmacro %}
{{advance('LR7', 'first')}}
{{advance('LR14', 'second')}}
INC LR10 1 ;;
BLT.S LR10 {{cr.in0_d1}} patch_channel ;;
INC LR5 1 ; SET LR14 LR3 ;;
INC LR14 {{kh}} ;;
BLT.S LR5 LR14 ky ;;

SET LR6 CR0 ; SET LR8 CR0 ; SET LR11 LR2 ;;
INC LR8 125 ;;
{% macro seed(acc) %}
 LD.MULT.CYCLIC LR6 {{cr.weights}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{full}} {{qi}} ; {{acc}} ; INC LR6 1 ;;
{% endmacro %}
output_channel:
{{seed('ACC.ADD.FIRST')}}
{{seed('ACC.ADD')}}
SET LR12 CR0 ;;
INC LR12 1 ;;
digit:
SET LR4 CR0 ; SET LR10 CR0 ;;
{% if taps // 128 %}
panel:
{{reduce_panel(128, 'full', 'LR8')}}
INC LR10 1 ;;
{% if rt %}
SET LR14 LR15 ;;
DEC LR14 1 ;;
BLT.S LR10 LR14 panel ;;
{% else %}
BLT.S LR10 LR15 panel ;;
{% endif %}
{% endif %}
{% if rt %}{{reduce_panel(rt, 'tail', 'LR9')}}{% endif %}
DEC LR12 1 ;;
BGE.S LR12 CR0 digit ;;
{% macro write_out(ds) %}
 ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}} {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
{% endmacro %}
{% if out0_d2 % 2 %}
SET LR14 LR3 ;;
INC LR14 {{stride}} ;;
BLT.S LR14 {{cr.yend}}.L store_pair ;;
{{write_out(cr.width ~ '.H')}}
B stored ;;
store_pair:
{% endif %}
{{write_out(width)}}
stored:
ADD LR2 LR2 {{cr.yend}}.H ;;
BLT.S LR6 {{cr.weight_rows}} output_channel ;;
SET LR2 LR11 ; INC LR3 {{stride * 2}} ;;
INC LR2 1 ;;
BLT.S LR3 {{cr.yend}}.L spatial_row ;;
HALT ;;
