{% set dw = groups == cin == cout %}
{% set ic = (in0_d1 + 127)//128 %}
{% set oc = (out0_d1 + 127)//128 %}
{% set pc = 1 if dw else ic %}
{% set period = 6-2*stride %}
{% set paired = not dw and kw == 3 and padding == 1 and out0_d2 % period == 0 and not (cin <= 128 and cout <= 384) %}
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
 SET LR11 {{ cr.copy_end }} ;;
{% if in0_d2*pc > 1 %}
copy_x:
 {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ ic if dw else 1 }} ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ pad_store('CR1') }} ;;
 {{ zeros('right',padding*pc) }}
{% if paired %}
{# Difference plane: D[p] = X[p] - X[p+2], with the same channel blocking. #}
 SET LR4 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
 DEC LR4 1 ; INC LR8 {{ 2*ic-1 }} ; INC LR9 1 ;;
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR10 {{ cr.copy_end }} ;;
 LD.MULT R1 LR8 {{ cr.pad }} ; INC LR8 1 ; SET LR6 CR0 ;;
{% macro difference(next) %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; {% if next %} LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;{% endif %} ;;
 MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.diff }} LR9 ; INC LR9 1 ; {% if next %} LD.MULT R1 LR8 {{ cr.pad }} ; INC LR8 1 ; INC LR6 1 ; BLT.S LR6 LR10 differences ;{% endif %} ;;
{% endmacro %}
{% if in0_d2*ic > 1 %}
differences:
 {{ difference(true) }}
{% endif %}
 {{ difference(false) }}
{% endif %}

{% macro dense_tap(x,c,plane) %}
 {% set lanes = [128,cin-128*c]|min %}
 SET LR14 CR0 ; SET LR15 CR0 ; LD.MULT R0 LR4 {{ plane }} ; INC LR4 1 ;;
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
{% macro dot(x,plane,offset) %}
 SET LR4 LR5 ;;
 INC LR4 {{ offset }} ;;
 {% for c in range(ic) %}{{ dense_tap(x,c,plane) }}{% endfor %}
{% endmacro %}
{% macro bias_start() %}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; INC LR13 1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% endmacro %}

{% if paired %}
{# Two outputs with input starts two apart share (a+c)*X[p+2]+bias.
   Save its quantized high part and residual before computing either output. #}
 SET LR11 CR1 ;;
paired_chunk:
 SET LR9 CR0 ;;
paired_phase:
 SET LR5 LR9 ; SET LR6 LR2 ; SET LR10 {{ cr.pair_end }} ;;
 DEC LR5 1 ;;
{% if stride == 1 %}
 BEQ LR9 CR0 output_pair ;;
 {% if ic > 1 %}INC LR5 {{ ic-1 }} ;{% endif %} INC LR6 {{ oc }} ;;
{% endif %}
output_pair:
 SET LR13 LR3 ;;
 {{ bias_start() }}
 {{ dot('shared',cr.pad,2*ic) }}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.diff }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.diff }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.diff }} LR11 ;;
{% macro reload_shared() %}
 LD.MULT R0 LR0 {{ cr.diff }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R0 LR11 {{ cr.diff }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
{% endmacro %}
 {{ reload_shared() }}
 {{ dot('left_diff',cr.diff,2) }}
 {{ dot('left_mid',cr.pad,ic) }}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR6 ; SET LR8 LR6 ;;
 INC LR8 {{ (2//stride)*oc }} ;;
 {{ reload_shared() }}
 {{ dot('right_diff',cr.diff,2+2*ic) }}
 {{ dot('right_mid',cr.pad,3*ic) }}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR6 {{ period*oc }} ; INC LR5 {{ period*stride*ic }} ; DEC LR10 1 ; BLT.S CR0 LR10 output_pair ;;
{% if stride == 1 %}
 BEQ LR9 CR0 paired_phase ; INC LR9 1 ;;
{% endif %}
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 paired_chunk ;;
{% else %}
output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR10 CR0 ;;
 SET LR8 LR2 ;;
 DEC LR5 1 ; DEC LR8 {{ oc }} ;;
 SET LR10 {{ cr.pixel_end }} ;;
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
{% for x in range(kw) %}{% for c in range(ic) %}{{ dense_tap(x,c,cr.pad) }}{% endfor %}{% endfor %}
{% endif %}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride*pc }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 {{ 'stage_plane' if dw else 'output_chunk' }} ;;
{% endif %}
 HALT ;;
