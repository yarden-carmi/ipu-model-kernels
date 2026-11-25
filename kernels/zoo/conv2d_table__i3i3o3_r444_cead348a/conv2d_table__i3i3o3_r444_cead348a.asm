{% set ds = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set act = 'generic' if act_out0 == 'silu' else act_out0 %}
{% set ir = (in1_d2*in1_d3+127)//128 %}
{% set partial = (in1_d2*in1_d3)%128 != 0 %}
{% macro init(r,n) %}
SET {{ r }} CR0 ;;
{% for j in range(0,n|abs,255) %}
{{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,n|abs-j]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro zero_guard() %}
MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ;;
INC LR1 128 ;;
{{ init('LR2',-1) }}
{{ init('LR3',-1) }}
{{ init('LR4',0) }}
{{ init('LR5',cin-1) }}
{{ init('LR6',ir-1) }}

# The frozen graph convolves in1; in0 is handed in but is not an operand.
# Copy the live input into independently zero-guarded channel planes.
copy_channel:
{{ zero_guard() }}
SET LR8 CR0 ;;
copy_row:
{% if partial %} BEQ LR8 LR6 copy_tail ;; {% endif %}
{% macro copy_row_ops(valid) %}
LD.MULT R0 LR2 {{ cr.in1 }} ; INC LR2 1 ;;
MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ valid }} {{ qi }} {{ cr.guard }} LR3 ; INC LR3 1 ;
{% endmacro %}
{% if ir > 1 or not partial %}
{{ copy_row_ops(ds) }} INC LR8 1 ; BLT.S LR8 LR6 copy_row ;;
{% endif %}
{% if partial %}
{% if ir > 1 %}BEQ CR0 CR0 copy_complete ;;{% endif %}
copy_tail:
{{ copy_row_ops(tail) }} ;;
copy_complete:
{% endif %}
{{ zero_guard() }}
INC LR4 1 ; BLT.S LR4 LR5 copy_channel ;;

# Align each of the nine taps once per input channel and spatial tile.
{{ init('LR2',-1) }}
{{ init('LR4',0) }}
{{ init('LR13',1) }}
stage_channel:
SET LR3 LR13 ; SET LR8 CR0 ;;
stage_tile:
{% macro tap(d) %}
SET LR6 LR3 ; SET LR7 LR0 ;;
{% if d < 0 %} DEC LR6 1 ;; {% endif %}
LD.MULT.CYCLIC LR6 {{ cr.guard }} LR0 {% if d %}; INC LR7 {{ d%128 }}{% endif %} ;;
{% if d %} LD.MULT.CYCLIC LR6 {{ cr.guard }} LR1 ; INC LR6 1 ;; {% endif %}
MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;
ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stencil }} LR2 ; INC LR2 1 ;;
{% endmacro %}
{% for ky in range(3) %}{% for kx in range(3) %}
{{ tap((ky-1)*in1_d3+kx-1) }}
{% endfor %}{% endfor %}
INC LR3 1 ; INC LR8 1 ; BLT.S LR8 LR15 stage_tile ;;
INC LR13 {{ ir+2 }} ; INC LR4 1 ; BLT.S LR4 LR5 stage_channel ;;

{{ init('LR2',-1) }}
{% for j in range(5) %}
LD.LUT {{ j }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
{% endfor %}
{{ init('LR2',-1) }}
{{ init('LR4',0) }}
{{ init('LR5',cout-1) }}
{{ init('LR7',-1) }}
{{ init('LR12',128) }}
{{ init('LR14',cin-1) }}
output_channel:
SET LR6 CR0 ; SET LR10 LR0 ;;
DEC LR10 1 ;;
output_tile:
SET LR8 LR7 ;;
LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
LD.MULT.CYCLIC LR8 {{ cr.weights }} LR12 ; INC LR8 1 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ; SET LR9 LR10 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR0 ; INC LR8 1 ;;
MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; SET LR11 CR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
input_channel:
SET LR1 LR9 ;;
{% macro product() %}
LD.MULT.CYCLIC LR1 {{ cr.stencil }} LR0 ; INC LR1 1 ;;
LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ; LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ;;
MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;
{%- endmacro %}
{% for j in range(9) %}
{{ product() }} {% if loop.last %} ADD LR9 LR9 {{ cr.plane }} ; INC LR11 1 ; BLT.S LR11 LR14 input_channel ; {% endif %} ;;
{% endfor %}
{% if partial %} BEQ LR6 LR15 store_tail ;; {% endif %}
{% if ir > 1 or not partial %}
ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ; INC LR10 9 ; INC LR6 1 ; BLT.S LR6 LR15 output_tile ;;
{% endif %}
{% if partial %}
{% if ir > 1 %}BEQ CR0 CR0 next_channel ;;{% endif %}
store_tail:
ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR2 ; INC LR2 1 ;;
next_channel:
{% endif %}
SET LR7 LR8 ; INC LR4 1 ; BLT.S LR4 LR5 output_channel ;;
HALT ;;
