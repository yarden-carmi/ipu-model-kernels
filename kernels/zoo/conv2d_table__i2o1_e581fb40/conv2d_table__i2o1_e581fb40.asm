{% set dense = groups == 1 %}
{% set ic = (in0_d1 + 127) // 128 %}
{% set oc = (out0_d1 + 127) // 128 %}
{% set pc = ic if dense else 1 %}
{% set pack = 2 if in0_d2 <= 64 else 1 %}
{% set tiles = (in0_d2 + 127) // 128 %}
{% set pitch = ((in0_d3 + pack - 1) // pack) * tiles %}
{% set fast_gather = in0_d1 % 128 == 0 and pitch <= 255 %}
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
{% macro zeros(label, count) %}
 SET LR14 CR0 ;;
 {{ step('LR14', count) }}
{{ label }}:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; DEC LR14 1 ;;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stage }} LR9 ; INC LR9 1 ;;
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stage }} LR12 ; ADD LR12 LR9 {{ cr.stage_rows }} ; BNE LR14 CR0 {{ label }} ;;
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

# Transpose the packed height columns into channel vectors, adding a halo.
stage_plane:
 SET LR15 CR0 ;;
{% if not dense and oc > 1 %}
 SET LR14 CR0 ; SET LR13 LR2 ;;
 {{ step('LR14', pitch) }}
{% for i in range(7) %}
 ADD LR14 LR14 LR14 ;;
{% endfor %}
 BEQ LR13 CR0 plane_ready ;;
plane_base:
 ADD LR15 LR15 LR14 ; DEC LR13 1 ;;
 BNE LR13 CR0 plane_base ;;
plane_ready:
{% endif %}
 SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
 SET LR9 CR0 ; LD.MULT R0 LR0 {{ cr.in0 }} ;;
 DEC LR9 1 ;;
 {{ step('LR6', in0_d2) }}
 {{ zeros('top', (wp + 1) * pc) }}
stage_y:
 SET LR8 LR4 ; SET LR10 LR5 ; SET LR7 CR0 ;;
 {{ step('LR7', in0_d3) }}
{% if fast_gather %}
 SET LR14 CR0 ;;
 INC LR14 126 ;;
{% endif %}
stage_x:
 ADD LR11 LR15 LR8 ; SET LR13 CR0 ;;
 INC LR13 {{ pc }} ;;
stage_chunk:
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; SET LR12 CR0 ;;
{% if fast_gather %}
 DEC LR12 1 ;;
stage_channel:
 LD.MULT R0 LR11 {{ cr.in0 }} ;;
 MULT.EE LR10 CR1 0 LR0 {{ ds }} {{ qi }} ; AGG.SUM LR12 {{ cr.ds1 }}.L ; INC LR12 1 ; INC LR11 {{ pitch }} ; BLT.S LR12 LR14 stage_channel ;;
{% else %}
stage_channel:
 LD.MULT R0 LR11 {{ cr.in0 }} ;;
 MULT.EE LR10 CR1 0 LR0 {{ ds }} {{ qi }} ; AGG.SUM LR12 {{ cr.ds1 }}.L ;;
 INC LR12 1 ;;
 {{ step('LR11', pitch) }}
 BGE.S LR11 {{ cr.input_rows }} stage_store ;;
 BLT.S LR12 LR1 stage_channel ;;
{% endif %}
stage_store:
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stage }} LR9 ; INC LR9 1 ; DEC LR13 1 ;;
 LD.MULT R0 LR9 {{ cr.stage }} ; ADD LR12 LR9 {{ cr.stage_rows }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stage }} LR12 ;;
 BNE LR13 CR0 stage_chunk ;;
 DEC LR7 1 ;;
 BEQ LR7 CR0 stage_edge ;;
{% if pack == 2 %}
 BNE LR10 LR5 next_pair ;;
 INC LR10 {{ in0_d2 }} ; B stage_x ;;
next_pair:
 SET LR10 LR5 ;;
{% endif %}
 INC LR8 {{ tiles }} ; B stage_x ;;
stage_edge:
 {{ zeros('edges', 2 * pc) }}
 INC LR5 1 ; DEC LR6 1 ;;
{% if tiles > 1 %}
 BLT.S LR5 LR1 stage_y_next ;;
 SET LR5 CR0 ; INC LR4 1 ;;
stage_y_next:
{% endif %}
 BNE LR6 CR0 stage_y ;;
 {{ zeros('bottom', (wp - 1) * pc) }}

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
 MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;;
 SET LR9 CR0 ;;
 INC LR9 127 ;;
{% macro dense_tap(t) %}
 SET LR12 CR0 ;;
 {{ step('LR12', cin - 1) }}
dchunk{{ t }}:
 SET LR14 CR0 ; SET LR15 LR12 ;;
 DEC LR14 1 ; BLT.S LR12 LR9 dload{{ t }} ;;
 SET LR15 LR9 ;;
dload{{ t }}:
 LD.MULT R0 LR4 {{ cr.stage }} ; INC LR4 1 ;;
 LD.MULT R1 LR7 {{ cr.stage }} ; ADD LR7 LR4 {{ cr.stage_rows }} ;;
 SET LR7 LR1 ;;
 DEC LR7 1 ;;
scalar{{ t }}:
 MULT.RC.VE LR0 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ; INC LR14 1 ;;
 MULT.RC.VE LR0 LR7 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; INC LR7 1 ;;
 MULT.RC.VE LR1 LR14 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VE LR1 LR7 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; BLT.S LR14 LR15 scalar{{ t }} ;;
{% if ic > 1 %}
 DEC LR12 128 ;;
 BGE.S LR12 CR0 dchunk{{ t }} ;;
{% endif %}
{% endmacro %}
 SET LR11 LR7 ;;
{% for t in range(9) %}
 {{ dense_tap(t) }}
{% if t == 2 or t == 5 %}
 {{ step('LR4', (wp - 3) * pc) }}
{% endif %}
{% endfor %}
 SET LR7 LR11 ;;
 SET LR11 CR0 ;;
 {{ step('LR11', out0_d2) }}
 {{ pair('CR1', 'MULT.RC.VE') }}
{% else %}
 {{ pair('CR1', 'MULT.RC.VE', first=true) }}
{% macro depth_tap() %}
 LD.MULT R0 LR4 {{ cr.stage }} ; INC LR4 1 ;;
 LD.MULT R1 LR12 {{ cr.stage }} ; ADD LR12 LR4 {{ cr.stage_rows }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR1 ; INC LR13 1 ;;
 MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT.CYCLIC LR13 {{ cr.weights }} LR0 ; INC LR13 1 ;;
 MULT.RC.VV LR1 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
{% endmacro %}
{% for t in range(9) %}
 {{ depth_tap() }}
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
