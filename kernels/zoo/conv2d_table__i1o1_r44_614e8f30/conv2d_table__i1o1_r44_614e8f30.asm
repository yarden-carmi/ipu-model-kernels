{% set dw = groups == cin and cin == cout %}
{% set packed = out0_d1 <= 64 %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = 1 if dw else ic %}
{% set wp = in0_d3 + 2 * padding %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 in ['hardswish', 'silu', 'gelu', 'sigmoid', 'tanh'] else act_out0 %}
{% macro step(r, n) %}
 {% for k in range(0, n, 255) %}
 INC {{ r }} {{ [255, n-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro pad_store(src) -%}
 MULT.VE LR0 {{ src }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds_tail ~ '.L' if packed and dw else ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zeros(label, count) %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15', count - 1) }}
{{ label }}:
 {{ pad_store('CR0') }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endmacro %}
{% macro coeff(index, advance=true) -%}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} {{ index }} {% if advance %}; INC LR13 1{% endif %}
{%- endmacro %}
{% macro mac(op, idx, src, mode='ADD') -%}
 MULT.RC.{{ op }} {{ idx }} {{ src }} 0 LR0 {{ ds }} {{ qw }} ; ACC.{{ mode }}
{%- endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;

{# Stage zero-padded input, one channel chunk at a time for depthwise. #}
stage_plane:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
 DEC LR9 1 ; SET LR11 CR0 ;;
 {{ step('LR11', in0_d3 * pc - 2) }}
 {{ zeros('top', (wp + 1) * padding * pc) }}
 SET LR12 CR0 ;;
 {{ step('LR12', in0_d2) }}
copy_y:
 SET LR6 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
{% if in0_d3 * pc > 1 %}
copy_x:
 {{ pad_store('CR1') }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ ic if dw else 1 }} ; BLT.S LR6 LR11 copy_x ;;
{% endif %}
 {{ pad_store('CR1') }} ; INC LR10 {{ ic if dw else 1 }} ;;
 {{ zeros('edges', 2 * padding * pc) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zeros('bottom', (wp - 1) * padding * pc) }}

{% if packed %}
{# LR3 and LR12 name shifted cyclic windows for the second pixel. #}
 SET LR2 LR1 ; SET LR3 LR1 ; SET LR12 LR1 ;;
 INC LR2 128 ; DEC LR3 {{ cout }} ; INC LR12 {{ 128-cout }} ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ;;
{% endif %}
output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 {{ 'LR0' if packed else 'LR2' }} ; SET LR10 CR0 ;;
 DEC LR8 {{ oc }} ; DEC LR5 1 ;;
 {{ step('LR10', out0_d3 // (2 if packed else 1) - 1) }}
pixel:
 SET LR4 LR5 ; SET LR13 {{ 'LR0' if packed else 'LR3' }} ;;
 {{ coeff('LR1' if packed else 'LR0', false) }} ; SET LR9 CR0 ;;
 {{ coeff('LR2' if packed else 'LR1') }} ; INC LR9 {{ kh }} ;;
 {{ mac('VE', 'LR1' if packed else 'LR0', 'CR1', 'ADD.FIRST') }} ; INC LR13 1 ;;
 {{ mac('VE', 'LR2' if packed else 'LR1', 'CR1') }} ;;

kernel_y:
{% macro ordinary_tap(x) %}
 {% if dw %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 {{ coeff('LR0', false) }} ;;
 {{ coeff('LR1') }} ;;
 {{ mac('VV', 'LR0', 'R0') }} ; INC LR13 1 ;;
 {{ mac('VV', 'LR1', 'R0') }} ;;
 {% else %}
 {% for c in range(ic) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ; SET LR14 CR0 ; SET LR15 CR0 ;;
 DEC LR14 1 ; INC LR15 {{ [128, cin - 128*c]|min - 1 }} ;;
scalar_{{ x }}_{{ c }}:
 {{ coeff('LR0', false) }} ;;
 {{ coeff('LR1') }} ;;
 {{ mac('VE', 'LR0', 'LR14') }} ; INC LR13 1 ; INC LR14 1 ;;
 {{ mac('VE', 'LR1', 'LR14') }} ; BLT.S LR14 LR15 scalar_{{ x }}_{{ c }} ;;
 {% endfor %}
 {% endif %}
{% endmacro %}
{% macro packed_tap(x) %}
 SET LR14 LR4 ;;
 INC LR14 {{ stride * pc + 1 }} ;;
 {% if dw %}
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ; INC LR4 1 ;;
 LD.MULT.CYCLIC LR14 {{ cr.pad }} LR1 ;;
 LD.MULT R0 LR13 {{ cr.weights }} ;;
 LD.MULT R1 LR13 {{ cr.weights }} ; INC LR13 1 ;;
 {{ mac('VV', 'LR0', 'R0') }} ; INC LR13 1 ;;
 {{ mac('VV', 'LR3', 'R0') }} ;;
 {{ mac('VV', 'LR0', 'R1') }} ;;
 {{ mac('VV', 'LR3', 'R1') }} ;;
 {% else %}
 {% for c in range(ic) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 LD.MULT R1 LR14 {{ cr.pad }} ; SET LR15 LR1 ; SET LR11 CR0 ;;
 {{ step('LR11', [128, cin - 128*c]|min - 1) }}
 {# LR14 is the scalar index; recover the second input address per chunk. #}
 SET LR14 CR0 ; DEC LR15 1 ;;
 DEC LR14 1 ;;
packed_scalar_{{ x }}_{{ c }}:
 {{ coeff('LR1', false) }} ;;
 {{ coeff('LR2') }} ;;
 {{ mac('VE', 'LR1', 'LR14') }} ; INC LR14 1 ; INC LR13 1 ;;
 {{ mac('VE', 'LR3', 'LR15') }} ; INC LR15 1 ;;
 {{ mac('VE', 'LR2', 'LR14') }} ;;
 {{ mac('VE', 'LR12', 'LR15') }} ; BLT.S LR14 LR11 packed_scalar_{{ x }}_{{ c }} ;;
 {% if not loop.last %}
 SET LR14 LR4 ;;
 INC LR14 {{ stride * pc + 1 }} ;;
 {% endif %}
 {% endfor %}
 {% endif %}
{% endmacro %}
{% for x in range(kw) %}
 {% if packed %}{{ packed_tap(x) }}{% else %}{{ ordinary_tap(x) }}{% endif %}
{% endfor %}
 ADD LR4 LR4 {{ cr.window_jump }} ; DEC LR9 1 ;;
 BNE LR9 CR0 kernel_y ;;
{% macro store(active) -%}
 ACTIVATE.QUANTIZE {{ act }} {{ active }}.L {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }}
{%- endmacro %}
{% if not packed and oc > 1 and out0_d1 % 128 %}
 SET LR15 CR0 ;;
 INC LR15 {{ oc-1 }} ;;
 BEQ LR2 LR15 tail ;;
 {{ store(cr.ds_out) }} ; B advance ;;
tail:
 {{ store(cr.ds_tail) }} ;;
advance:
{% else %}
 {{ store(cr.ds_out) }} ;;
{% endif %}
 INC LR5 {{ stride * pc * (2 if packed else 1) }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - out0_d3) * pc) }}
 BLT.S LR7 {{ cr.out0_d2 }} pixel ;;
{% if not packed %}
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 CR0 ;;
 INC LR15 {{ oc }} ;;
 BLT.S LR2 LR15 {{ 'stage_plane' if dw else 'output_chunk' }} ;;
{% endif %}
 HALT ;;
