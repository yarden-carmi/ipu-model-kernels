{% set dw = groups == cin == cout %}
{% set ic = (in0_d1 + 127)//128 %}
{% set oc = (out0_d1 + 127)//128 %}
{% set pc = 1 if dw else ic %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 == 'gelu' else act_out0 %}
{% macro step(r,n) %}
{% for k in range(0,n,255) %} INC {{ r }} {{ [255,n-k]|min }} ;; {% endfor %}
{% endmacro %}
{% macro pad_store(src) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zeros(label,count) %}
{% if count %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15',count-1) }}
{{ label }}:
 {{ pad_store('CR0') }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endif %}
{% endmacro %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
stage_plane:
 SET LR9 CR0 ; SET LR10 LR2 ;;
 DEC LR9 1 ;;
 {{ zeros('left',padding*pc) }}
 SET LR6 CR0 ; SET LR11 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
 {{ step('LR11',in0_d2*pc-2) }}
{% if in0_d2*pc > 1 %}
copy_x:
 {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ ic if dw else 1 }} ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ pad_store('CR1') }} ;;
 {{ zeros('right',padding*pc) }}
output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR10 CR0 ;;
 SET LR8 LR2 ;;
 DEC LR5 1 ; DEC LR8 {{ oc }} ;;
 {{ step('LR10',out0_d2-1) }}
pixel:
 SET LR4 LR5 ; SET LR13 LR3 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
{% if dw %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
{% macro depth_tap(last) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if not last %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;{% endif %} ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {% if not last %}LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;{% endif %} ;;
{% endmacro %}
{% for t in range(kw) %}{{ depth_tap(loop.last) }}{% endfor %}
{% else %}
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% macro dense_tap(x,c) %}
 {% set lanes = [128,cin-128*c]|min %}
 SET LR14 CR0 ; SET LR15 CR0 ; LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 DEC LR14 1 ; INC LR15 {{ lanes }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {% if lanes > 1 %}
 DEC LR15 2 ;;
scalar_{{ x }}_{{ c }}:
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; BLT.S LR14 LR15 scalar_{{ x }}_{{ c }} ;;
 {% endif %}
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR14 1 ; INC LR13 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% endmacro %}
{% for x in range(kw) %}{% for c in range(ic) %}{{ dense_tap(x,c) }}{% endfor %}{% endfor %}
{% endif %}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride*pc }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 {{ 'stage_plane' if dw else 'output_chunk' }} ;;
 HALT ;;
