{% set pitch = (in0_d3 + 2 * padding) * ic %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set act = act_out0|default('identity') %}
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

 SET LR0 CR0 ;;
{% if padding %}
 SET LR9 CR0 ; SET LR10 CR0 ; SET LR7 CR0 ;;
 DEC LR9 1 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 {{ step('LR11', in0_d3 * ic - 2) }}
 {{ step('LR12', in0_d2) }}
 {{ zeros('top', pitch + ic) }}
copy_y:
 SET LR6 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% if in0_d3 * ic > 1 %}
copy_x:
 {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 1 ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ pad_store('CR1') }} ; INC LR10 1 ;;
 {{ zeros('edges', 2 * ic) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zeros('bottom', pitch - ic) }}
{% endif %}

{# A full width row stays in the accumulator until its final store. #}
{% macro term() %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; AGG.SUM LR9 {{ ds }}
{%- endmacro %}
{% macro weight() %}
 LD.MULT.CYCLIC LR12 {{ cr.weights }} LR0 ; INC LR12 1
{%- endmacro %}
{% macro tap() %}
 LD.MULT R0 LR11 {{ cr.pad if padding else cr.in0 }} ; INC LR11 1 ;;
 {{ weight() }} ;;
 {{ term() }} ; {{ weight() }} ;;
 {{ term() }} ; {{ weight() }} ;;
 {{ term() }} ;;
{% endmacro %}

 SET LR2 CR0 ; SET LR3 CR0 ; SET LR15 CR0 ;;
 INC LR15 {{ kh }} ; SET LR10 CR0 ;;
 INC LR10 {{ out0_d3 - 1 }} ;;
channel:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR8 LR2 ;;
 DEC LR5 1 ;;
output_y:
 SET LR7 LR5 ; SET LR9 CR0 ; SET LR12 LR3 ;;
 DEC LR12 1 ;;
 {{ weight() }} ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; {{ weight() }} ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; {{ weight() }} ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
pixel:
 SET LR11 LR7 ; SET LR12 LR3 ; SET LR13 CR0 ;;
 INC LR12 2 ;;
ky:
 SET LR14 CR0 ;;
 INC LR14 {{ kw }} ;;
kx:
{% for c in range(ic) %}
 {{ tap() }}
{% endfor %}
 DEC LR14 1 ;;
 BLT.S CR0 LR14 kx ;;
 {{ step('LR11', pitch - kw * ic) }}
 INC LR13 1 ;;
 BLT.S LR13 LR15 ky ;;
 INC LR7 {{ stride * ic }} ; INC LR9 1 ; BLT.S LR9 LR10 pixel ;;
 ACTIVATE.QUANTIZE {{ act }} {{ cr.dstail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
 ADD LR8 LR8 {{ cr.cout }} ; ADD LR5 LR5 {{ cr.pitch }} ; INC LR6 1 ;;
 BLT.S LR6 {{ cr.out0_d2 }} output_y ;;
 ADD LR3 LR3 {{ cr.weight_block }} ; INC LR2 1 ;;
 BLT.S LR2 {{ cr.cout }} channel ;;
 HALT ;;
