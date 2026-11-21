{# Gather column-major input into a padded, channel-vector image. #}
{% set dense = not (groups == cin and cin == cout) %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = ic if dense else 1 %}
{% set wp = in0_d3 + 2 %}
{% set pack = 2 if in0_d2 <= 64 and in0_d3 % 2 == 0 else 1 %}
{% set hc = (in0_d2 + 127) // 128 %}
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
{% macro clear() %}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST
{%- endmacro %}
{% macro store_pad() %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1
{%- endmacro %}
{% macro zero_loop(label, count) %}
 SET LR14 CR0 ; SET LR15 CR0 ;;
 {{ step('LR15', count - 1) }}
{{ label }}:
 {{ clear() }} ; {{ store_pad() }} ;;
 {{ store_pad() }} ; INC LR14 1 ; BLT.S LR14 LR15 {{ label }} ;;
{% endmacro %}
{% macro gather(p) %}
 SET LR8 LR4 ; SET LR13 LR5 ;;
{% if p %}
 INC LR13 {{ in0_d2 }} ;;
{% endif %}
{% for c in range(pc) %}
{% set n = [128, cin - c * 128]|min if dense else (cin % 128 or 128) %}
 {{ clear() }} ; SET LR11 CR0 ; SET LR12 CR0 ; SET LR14 CR0 ;;
{% if not dense and cin > 128 and n != 128 %}
 INC LR14 127 ; SET LR15 {{ cr.oc }} ;;
 DEC LR15 1 ; BNE LR2 LR15 collect{{ p }}_{{ c }} ;;
 DEC LR14 {{ 128-n }} ;;
{% else %}
 {{ step('LR14', n - 1) }}
{% endif %}
collect{{ p }}_{{ c }}:
 LD.MULT R0 LR8 {{ cr.in0 }} ;;
 MULT.EE LR13 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD10 7 ;;
 ADDBI LRD10 1 ; ADD LR8 LR8 {{ cr.plane_rows }} ; INC LR12 1 ; BLT.S LR12 LR14 collect{{ p }}_{{ c }} ;;
 {{ store_pad() }} ;;
 LD.MULT R0 LR9 {{ cr.pad }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; {{ store_pad() }} ;;
{% endfor %}
{% endmacro %}
{% macro pair(src, op, first=false) %}
 {{ op }} LR0 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 {{ op }} LR1 {{ src }} 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR13 CR0 ;;
 DEC LR13 1 ;;
{% for i in range(5) %}
 LD.LUT {{ i }} {{ cr.lut }} LR13 ; INC LR13 1 ;;
{% endfor %}
 SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR3 1 ;;
stage_plane:
 SET LR1 CR0 ; SET LR5 CR0 ; SET LR7 CR0 ;;
 SET LR9 CR0 ;;
{% if not dense and oc > 1 %}
 SET LR8 LR2 ; BEQ LR2 CR0 stage_start ;;
source_chunk:
 ADD LR1 LR1 {{ cr.chunk_pitch }} ; DEC LR8 1 ;;
 BNE LR8 CR0 source_chunk ;;
stage_start:
{% endif %}
 DEC LR9 1 ;;
 {{ zero_loop('top', (wp + 1) * pc) }}
copy_y:
 SET LR4 LR1 ; SET LR6 CR0 ;;
copy_x:
{% for p in range(pack) %}
 {{ gather(p) }}
{% endfor %}
 SET LR15 CR0 ; INC LR4 {{ hc }} ; INC LR6 {{ pack }} ;;
 {{ step('LR15', in0_d3) }}
 BLT.S LR6 LR15 copy_x ;;
 {{ zero_loop('edges', 2 * pc) }}
 INC LR7 1 ; INC.MODP2 LR5 CR1 7 ; SET LR15 CR0 ;;
{% if hc > 1 %}
 BNE LR5 CR0 height_count ;;
 INC LR1 1 ;;
height_count:
{% endif %}
 {{ step('LR15', in0_d2) }}
 BLT.S LR7 LR15 copy_y ;;
 {{ zero_loop('bottom', (wp - 1) * pc) }}
 SET LR1 CR0 ;;
 INC LR1 128 ;;

output_chunk:
 SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
 SET LR8 LR2 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 DEC LR8 {{ oc }} ;;
 {{ step('LR10', out0_d3) }}
 {{ step('LR11', out0_d2) }}
pixel:
{% macro start_pixel(lo=false) %}
 SET LR4 LR5 ; SET LR13 LR3 ;;
{% if not lo %}
 DEC LR4 1 ;;
{% endif %}
 LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
{% endmacro %}
 {{ start_pixel() }}
{% if dense %}
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
 INC LR4 1 ;;
scalar{{ t }}:
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ; BLT.S LR14 LR15 scalar{{ t }} ;;
{% if ic > 1 %}
 DEC LR12 128 ;;
 BGE.S LR12 CR0 dchunk{{ t }} ;;
{% endif %}
{% endmacro %}
{% else %}
 {{ pair('CR1', 'MULT.RC.VE', first=true) }}
{% endif %}
{% macro taps(suffix) %}
{% for t in range(9) %}
{% if dense %}
 {{ dense_tap(suffix ~ t) }}
{% else %}
 LD.MULT R0 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 LD.MULT R1 LR4 {{ cr.pad }} ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VV LR1 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% endif %}
{% if t == 2 or t == 5 %}
 {{ step('LR4', 2 * (wp - 3) * pc) }}
{% endif %}
{% endfor %}
{% endmacro %}
 {{ taps('hi') }}
{% if dense %}
 {{ start_pixel(lo=true) }}
 {{ taps('lo') }}
 {{ pair('CR1', 'MULT.RC.VE') }}
{% endif %}
 ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR8 ; INC LR8 {{ oc }} ; INC LR5 {{ 2 * stride * pc }} ; INC LR6 1 ;;
 BLT.S LR6 LR10 pixel ;;
 INC LR7 1 ; SET LR6 CR0 ;;
 {{ step('LR5', 2 * stride * (wp - out0_d3) * pc) }}
 BLT.S LR7 LR11 pixel ;;
 INC LR2 1 ; ADD LR3 LR3 {{ cr.weight_block }} ; SET LR15 {{ cr.oc }} ;;
 BLT.S LR2 LR15 {{ 'output_chunk' if dense else 'stage_plane' }} ;;
 HALT ;;
