{% set oh = out0_d2 %}
{% set ow = out0_d3 %}
{% set ncol = 2 if oh <= 64 else 1 %}
{% set slab = [oh, 128 // stride]|min %}
{% set pair = ncol == 2 or oh > slab %}
{% set split = pair and (stride != 1 or oh > 8) %}
{% set ic = cin // groups %}
{% set oc = cout // groups %}
{% set ib = (in0_d2 + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% macro num(r, n) %}
 SET {{ r }} CR0 ;;
 {% for part in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, n|abs-part]|min }} ;;
 {% endfor %}
{% endmacro %}

{# Copy a shifted input column (or half-column) into its packed output lanes. #}
{% macro gather(id, xoff, block, dst) %}
 ADD LR7 LR10 LR11 ;;
 {% if xoff %}INC LR7 {{ xoff }} ;;{% endif %}
 BLT.S LR7 CR0 skip_{{ id }} ;;
 BGE.S LR7 {{ cr.in0_d3 }} skip_{{ id }} ;;
 ADD LR6 LR13 LR7 ;;
 {% if ib == 2 %}ADD LR6 LR6 LR7 ;;{% endif %}
 {% if block %}
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR4 ;;
 INC LR6 1 ;;
 {% endif %}
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR1 ;;
 SET LR0 {{ cr.src_a }} ; SET LR1 {{ cr.src_b }} ;;
 SET LR2 {{ cr.dst_a }} ; SET LR3 {{ cr.dst_b }} ;;
 {% if dst %}ADDBI LRD2 {{ dst }} ;;{% endif %}
 {% for i in range(slab // 8) %}
 {% if not loop.first %}ADDBI LRD0 {{ 8 * stride }} ; ADDBI LRD2 8 ;;{% endif %}
 MULT.RC.VE LR12 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 {% endfor %}
 {% if stride == 1 %}
 {# Do not consume the padded lane just past the true bottom edge. #}
 {{ num('LR7', 129) }}
 BNE LR12 LR7 skip_{{ id }} ;;
 MULT.RC.VE LR12 CR0 0 LR4 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 {% endif %}
 {% if block %}LD.MULT.CYCLIC LR4 {{ cr.pad }} LR4 ;;{% endif %}
 skip_{{ id }}:
{% endmacro %}

{# Two coefficient rows per block. The low MAC prefetches the next window. #}
{% macro macs(n, again=false) %}
 LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ; SUB LR3 LR4 CR1 ;;
 LD.MULT R1 LR2 {{ cr.weights }} ; INC LR2 1 ; SET LR6 CR0 ;;
 INC LR6 127 ;;
 {{ num('LR0', n * 9 - 1) }}
 mac_channel_{{ n }}:
 {% for tap in range(9) %}
 MULT.RC.VE LR4 LR3 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1 ;;
 {% if split %}
 MULT.RC.VE LR4 LR6 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR6 1 ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR4 ; INC LR1 1 ;;
 MULT.RC.VE LR4 LR3 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD ;;
 {% endif %}
 MULT.RC.VE LR4 LR6 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD ; {% if not split %}INC LR6 1 ;{% endif %} LD.MULT.CYCLIC LR1 {{ cr.pad }} LR4 ; INC LR1 1 ; {% if loop.last and n > 1 %}BLT.S LR3 LR0 mac_channel_{{ n }} ;{% endif %} ;;
 {% endfor %}
 {% if again %}INC LR7 1 ; BLT.S LR7 LR12 coeff_block ;;{% endif %}
{% endmacro %}

{{ num('LR4', 0) }}
{{ num('LR2', -1) }}
{% for j in range(5) %}
 LD.LUT {{ j }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
{% endfor %}
{{ num('LR5', -groups) }}
{{ num('LR9', 0) }}
{{ num('LR14', 0) }}
{{ num('LR15', -1) }}
MULT.VE LR4 CR0 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR4 ;;

group_loop:
{{ num('LR1', 256) }}
LD.MULT.CYCLIC LR4 {{ cr.pad }} LR4 ;;
LD.MULT.CYCLIC LR4 {{ cr.pad }} LR1 ; SET LR8 CR0 ; SET LR10 CR0 ;;
stage_tile:
SET LR13 LR9 ;;
stage_channel:
{{ num('LR12', 127) }}
stage_y:
{{ num('LR11', -1) }}
stage_x:
MULT.RC.VE LR4 CR0 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{{ num('LR1', 128) }}
{{ gather('first', 0, 0, 0) }}
{% if split %}
INC LR8 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR8 ;;
MULT.RC.VE LR4 CR0 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% endif %}
{% if pair %}
{{ num('LR1', 128) }}
{{ gather('second', stride if ncol == 2 else 0, 0 if ncol == 2 else 1, slab) }}
{% endif %}
INC LR8 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR8 ; INC LR11 1 ;;
{{ num('LR7', 2) }}
BLT.S LR11 LR7 stage_x ;;
INC LR12 1 ;;
{{ num('LR7', 130) }}
BLT.S LR12 LR7 stage_y ;;
ADD LR7 LR9 {{ cr.group_rows }} ; INC LR13 {{ (in0_d3 * ib) % 256 }} ;;
{% for k in range((in0_d3 * ib) // 256) %}INC LR13 255 ;; INC LR13 1 ;;{% endfor %}
BLT.S LR13 LR7 stage_channel ;;
{{ num('LR7', ow * stride) }}
INC LR10 {{ ncol * stride }} ;;
BLT.S LR10 LR7 stage_tile ;;
INC LR8 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR8 ; SET LR9 LR13 ;;

{{ num('LR11', -oc) }}
{{ num('LR12', ic // 14 - 1) }}
out_channel:
SET LR8 CR1 ; SET LR10 CR0 ;;
out_tile:
SUB LR1 LR8 CR1 ; SUB LR2 LR14 CR1 ; SET LR7 CR0 ;;
LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ; SET LR3 CR0 ;;
MULT.EE LR3 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R1 LR2 {{ cr.weights }} ; INC LR2 1 ;;
INC LR3 128 ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR4 ; INC LR1 1 ;;
MULT.EE LR3 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD ;;
{% if ic >= 14 %}
coeff_block:
{{ macs(14, true) }}
{% endif %}
{% if ic % 14 %}{{ macs(ic % 14) }}{% endif %}
INC LR15 1 ; ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ ds }} {{ qo }} {{ cr.out0 }} LR15 ; INC LR10 {{ ncol * stride }} ;;
SET LR8 LR1 ;;
{{ num('LR7', ow * stride) }}
BLT.S LR10 LR7 out_tile ;;
ADD LR14 LR2 CR1 ; INC LR11 1 ;;
BLT.S LR11 CR0 out_channel ;;
INC LR5 1 ;;
BLT.S LR5 CR0 group_loop ;;
HALT ;;
