{# Each spatial output lane is reduced directly into its final accumulator
   slot, without quantizing partial convolution results. #}
{% set dw = groups > 1 %}
{% set ic = (cin + 127) // 128 %}
{% set gc = cin // groups %}
{% set gic = (gc + 127) // 128 %}
{% set wp = in0_d3 + 2 * padding %}
{% set wo = out0_d3 %}
{% set ox = (wo + 127) // 128 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set dot = cr.ds1 ~ '.L' if dw else ds %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['silu', 'hardswish', 'gelu', 'sigmoid', 'tanh'] else act_out0 %}
{% macro step(r, n) %}
{% for k in range(0, n, 255) %}
 INC {{ r }} {{ [255, n-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro pad_store(src) %}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zeros(label, count) %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15', count - 1) }}
{{ label }}:
 {{ pad_store('CR0') }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR7 CR0 ;;
 DEC LR9 1 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 {{ step('LR11', in0_d3 * ic - 2) }}
 {{ step('LR12', in0_d2) }}
 {{ zeros('top', (wp * padding + padding) * ic) }}
copy_y:
 SET LR6 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% if in0_d3 * ic > 1 %}
copy_x:
 {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 1 ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ pad_store('CR1') }} ; INC LR10 1 ;;
 {{ zeros('edges', 2 * padding * ic) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zeros('bottom', (wp * padding - padding) * ic) }}

 SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
 SET LR8 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
 DEC LR8 1 ; INC LR15 {{ kh }} ;;
channel:
 SET LR5 LR4 ; SET LR6 CR0 ;;
 DEC LR5 1 ;;
output_y:
 SET LR7 LR5 ;;
{% macro term() %}
 {{ 'MULT.RC.VE LR0 LR14' if dw else 'MULT.RC.VV LR0 R0' }} 0 LR0 {{ dot }} {{ qw }} ; AGG.SUM LR9 {{ dot }}
{%- endmacro %}
{% macro weight() %}
 LD.MULT.CYCLIC LR12 {{ cr.weights }} LR0 ; INC LR12 1
{%- endmacro %}
{% macro tap() %}
 LD.MULT R0 LR11 {{ cr.pad }} ; INC LR11 1 ;;
 {{ weight() }} ;;
 {{ term() }} ; {{ weight() }} ;;
 {{ term() }} ; {{ weight() }} ;;
 {{ term() }} ;;
{% endmacro %}
{% macro tile(t, n) %}
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR12 LR3 ;;
 DEC LR12 1 ;;
 {{ step('LR10', n - 1) }}
 LD.MULT.CYCLIC LR12 {{ cr.weights }} LR0 ; INC LR12 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR12 {{ cr.weights }} LR0 ; INC LR12 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ weight() }} ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
pixel{{ t }}:
 SET LR11 LR7 ; SET LR12 LR3 ; SET LR13 CR0 ;;
 INC LR12 2 ;;
ky{{ t }}:
{% for k in range(kw) %}
 {% for c in range(gic) %}
  {{ tap() }}
 {% endfor %}
 {% if ic > gic %} {{ step('LR11', ic - gic) }} {% endif %}
{% endfor %}
 {{ step('LR11', (wp - kw) * ic) }}
 INC LR13 1 ;;
 BLT.S LR13 LR15 ky{{ t }} ;;
 INC LR7 {{ stride * ic }} ; INC LR9 1 ; BLT.S LR9 LR10 pixel{{ t }} ;;
 ACTIVATE.QUANTIZE {{ act }} {{ ds if n == 128 else cr.dstail ~ '.L' }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 1 ;;
{% endmacro %}
{% for t in range(ox) %}
 {{ tile(t, [128, wo - 128*t]|min) }}
{% endfor %}
 {{ step('LR5', stride * wp * ic) }}
 INC LR6 1 ;;
 BLT.S LR6 {{ cr.out0_d2 }} output_y ;;
 ADD LR3 LR3 {{ cr.weight_block }} ; INC LR2 1 ;;
{% if dw %}
 INC.MODP2 LR14 CR1 7 ;;
 BNE LR14 CR0 same_chunk ;;
 INC LR4 1 ;;
same_chunk:
{% endif %}
 BLT.S LR2 {{ cr.cout }} channel ;;
 HALT ;;
