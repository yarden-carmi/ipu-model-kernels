{% set iy = (in0_d2 + 127) // 128 %}
{% set oy = (out0_d2 + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro num(r, n) %}
 SET {{ r }} CR0 ;;
 {% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}

{{ num('LR1', 128) }}
{{ num('LR2', 256) }}
{{ num('LR3', 384) }}
{{ num('LR4', out0_d3) }}
{{ num('LR7', -1) }}
{{ num('LR13', 2) }}
LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.weights }} LR3 ;;
LD.MULT R0 LR0 {{ cr.weights }} ; INC LR0 1 ;;
DEC LR0 1 ;;
{% if iy == 1 %}LD.MULT.CYCLIC LR0 {{ cr.weights }} LR2 ;;{% endif %}

{# Each group owns a contiguous panel of [x, y tile, input channel, tap]. #}
{% macro stage(tile) %}
 SET LR5 LR11 ; SET LR9 CR0 ;;
stage_channel_{{ tile }}:
 {% for dx in [-1,0,1] %}
 {% set s = tile ~ '_' ~ loop.index %}
 {% if dx == -1 %}
 BEQ LR8 CR0 zero_{{ s }} ;;
 {% elif dx == 1 and (out0_d3-1)*stride+1 >= in0_d3 %}
 BEQ LR8 LR14 zero_{{ s }} ;;
 {% endif %}
 ADD LR6 LR5 LR12 ;;
 {% if dx == -1 %}DEC LR6 {{ iy }} ;;{% elif dx == 1 %}INC LR6 {{ iy }} ;;{% endif %}
 LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR1 ;;
 {% if iy == 2 %}LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR2 ; INC LR6 1 ;;{% endif %}
 {% if dx == -1 or (dx == 1 and (out0_d3-1)*stride+1 >= in0_d3) %}
 BEQ CR0 CR0 taps_{{ s }} ;;
zero_{{ s }}:
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR1 ;;
 {% if iy == 2 %}LD.MULT.CYCLIC LR0 {{ cr.weights }} LR2 ;;{% endif %}
taps_{{ s }}:
 {% endif %}
 {% for dy in [-1,0,1] %}
 SET LR15 {{ 'LR1' if tile == 0 else 'LR2' }} ;;
 {% if dy == -1 %}DEC LR15 1 ;;{% elif dy == 1 %}INC LR15 1 ;;{% endif %}
 {% if stride == 1 %}
 MULT.RC.{{ 'VV LR15 R0' if dy == 1 and tile == oy-1 else 'VE LR15 CR1' }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ tail if tile == oy-1 else full }} {{ qi }} {{ cr.pad }} LR7 ; INC LR7 1 ;;
 {% else %}
 MULT.RC.{{ 'VV LR15 R0' if dy == 1 and iy == 1 else 'VE LR15 CR1' }} 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ; {% if iy == 1 %}ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.pad }} LR7 ; INC LR7 1 ;{% endif %} ;;
 {% if iy == 2 %}
 MULT.RC.{{ 'VV LR15 R0' if dy == 1 else 'VE LR15 CR1' }} 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR13 ; ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.pad }} LR7 ; INC LR7 1 ; INC LR15 128 ;;
 {% endif %}
 {% endif %}
 {% endfor %}
 {% endfor %}
 ADD LR5 LR5 {{ cr.iplane }} ; INC LR9 1 ;;
 BLT.S LR9 {{ cr.ic }} stage_channel_{{ tile }} ;;
{% endmacro %}

SET LR14 LR4 ;;
DEC LR14 1 ;;
stage_group:
 SET LR8 CR0 ; SET LR12 CR0 ;;
stage_x:
 {% for tile in range(oy) %}{{ stage(tile) }}{% endfor %}
 INC LR12 {{ stride * iy }} ; INC LR8 1 ;;
 BLT.S LR8 LR4 stage_x ;;
 SET LR11 LR5 ; INC LR10 1 ;;
 BLT.S LR10 {{ cr.groups }} stage_group ;;
MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.pad }} LR7 ; INC LR7 1 ;;

{{ num('LR4', -1) }}
{% for j in range(5) %}LD.LUT {{ j }} {{ cr.lut }} LR4 ; INC LR4 1 ;;{% endfor %}
SET LR11 CR0 ; SET LR10 CR0 ; SET LR4 CR1 ;;
{{ num('LR7', -1) }}
{{ num('LR14', cout//groups) }}
SET LR15 {{ cr.ic }} ;;
DEC LR15 1 ;;

output_group:
 SET LR13 CR0 ;;
output_channel:
 SET LR12 LR11 ; SET LR8 CR0 ; SET LR9 CR0 ;;
output_row:
 SET LR5 LR4 ; SET LR6 LR12 ;;
 DEC LR6 1 ;;
 LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; LD.MULT.CYCLIC LR6 {{ cr.pad }} LR0 ; INC LR6 1 ;;
 SET LR3 CR0 ;;
coeff_channel:
 LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ; SUB LR1 LR0 CR1 ; SUB LR2 LR0 CR1 ;;
 LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ; INC LR1 128 ;;
 {% for tap in range(9) %}
 MULT.RC.VE LR0 LR2 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR2 1 ; LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 {{ 1 if loop.first else 2 }} ;;
 MULT.RC.VE LR0 LR2 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; {% if not loop.last %}LD.MULT R0 LR5 {{ cr.weights }} ; DEC LR5 2 ;{% endif %} ;;
 MULT.RC.VE LR0 LR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR1 1 ; LD.MULT.CYCLIC LR6 {{ cr.pad }} LR0 ; INC LR6 1 ; {% if loop.last %}INC LR3 1 ; BLT.S LR3 LR15 coeff_channel ;{% endif %} ;;
 {% endfor %}
 {% if oy == 2 and out0_d2 % 128 %}
 BEQ LR9 CR1 output_tail ;;
 ACTIVATE.QUANTIZE generic {{ full }} {{ qo }} {{ cr.out0 }} LR7 ; INC LR7 1 ; SET LR9 CR1 ; BEQ CR0 CR0 output_next ;;
output_tail:
 SET LR9 CR0 ;
 {% endif %}
 ACTIVATE.QUANTIZE generic {{ tail }} {{ qo }} {{ cr.out0 }} LR7 ; INC LR7 1 ;;
output_next:
 SET LR12 LR6 ; INC LR8 1 ;;
 BLT.S LR8 {{ cr.spatial }} output_row ;;
 SET LR4 LR5 ; INC LR13 1 ;;
 BLT.S LR13 LR14 output_channel ;;
 ADD LR11 LR11 {{ cr.group_rows }} ; INC LR10 1 ;;
 BLT.S LR10 {{ cr.groups }} output_group ;;
 HALT ;;
