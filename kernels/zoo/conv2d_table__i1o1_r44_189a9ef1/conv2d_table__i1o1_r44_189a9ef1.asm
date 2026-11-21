{# Channel chunks are interleaved by spatial position. Dense shares one
   padded image across output chunks; depthwise only stages its current plane. #}
{% set dense = groups == 1 %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = ic if dense else 1 %}
{% set wp = in0_d3 + 2 %}
{% set wo = out0_d3 %}
{% set ds = cr.ds128 ~ '.L' %}
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
{% macro zero_loop(label, count) %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15', count) }}
{{ label }}:
 {{ pad_store('CR0') }} ; INC LR14 1 ;;
 BLT.S LR14 LR15 {{ label }} ;;
{% endmacro %}
{% macro pair(src, op, first=false) %}
 {{ op }} LR0 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {{ op }} LR1 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR13 CR0 ;;
 INC LR1 128 ; DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR3 1 ;;
stage_plane:
 SET LR9 CR0 ; SET LR10 LR2 ; SET LR7 CR0 ;;
 DEC LR9 1 ; DEC LR10 {{ 1 if dense else ic }} ; SET LR11 CR0 ;;
 SET LR12 CR0 ;;
 {{ step('LR11', in0_d3 * pc) }}
 {{ step('LR12', in0_d2) }}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 {{ zero_loop('top', (wp + 1) * pc) }}
copy_y:
 SET LR6 CR0 ;;
copy_x:
 LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR6 1 ; INC LR10 {{ 1 if dense else ic }} ;;
 {{ pad_store('CR1') }} ; BLT.S LR6 LR11 copy_x ;;
 {{ zero_loop('edges', 2 * pc) }}
 INC LR7 1 ;;
 BLT.S LR7 LR12 copy_y ;;
 {{ zero_loop('bottom', (wp - 1) * pc) }}

output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ;;
 DEC LR8 {{ oc }} ; SET LR10 CR0 ; SET LR11 CR0 ;;
 {{ step('LR10', wo) }}
 {{ step('LR11', out0_d2) }}
pixel:
 SET LR4 LR5 ; SET LR13 LR3 ;;
 DEC LR4 1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% if dense %}
{# LR12 counts remaining channels minus one. LR15 is the final local
   scalar index in the current input chunk. #}
 MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;;
 SET LR9 CR0 ;;
 INC LR9 127 ;;
{% macro dense_tap(t) %}
 SET LR12 {{ cr.cm1 }} ;;
dchunk{{ t }}:
 SET LR14 CR0 ; SET LR15 LR12 ;;
 DEC LR14 1 ; BLT.S LR12 LR9 dload{{ t }} ;;
 SET LR15 LR9 ;;
dload{{ t }}:
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
scalar{{ t }}:
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; BLT.S LR14 LR15 scalar{{ t }} ;;
{% if ic > 1 %}
 DEC LR12 128 ;;
 BGE.S LR12 CR0 dchunk{{ t }} ;;
{% endif %}
{% endmacro %}
{% for t in range(9) %}
 {{ dense_tap(t) }}
{% if t == 2 or t == 5 %}
 {{ step('LR4', (wp - 3) * pc) }}
{% endif %}
{% endfor %}
 {{ pair('CR1', 'MULT.RC.VE') }}
{% else %}
 {{ pair('CR1', 'MULT.RC.VE', first=true) }}
{% for t in range(9) %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 {{ pair('R0', 'MULT.RC.VV') }}
{% if t == 2 or t == 5 %}
 {{ step('LR4', wp - 3) }}
{% endif %}
{% endfor %}
{% endif %}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ stride * pc }} ; INC LR6 1 ;;
 BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', stride * (wp - wo) * pc) }}
 BLT.S LR7 LR11 pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 {{ cr.oc }} ;;
 BLT.S LR2 LR15 {{ 'output_chunk' if dense else 'stage_plane' }} ;;
 HALT ;;
