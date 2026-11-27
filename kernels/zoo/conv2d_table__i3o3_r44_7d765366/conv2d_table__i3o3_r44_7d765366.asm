{% set width = in0_d3 %}
{% set ia = in0_d2 * width %}
{% set oa = out0_d2 * out0_d3 %}
{% set tiles = (oa + 127) // 128 %}
{% set wide = width >= 128 %}
{% set split = width == 256 %}
{% set segsize = 128 if stride == 1 else (64 if wide else 32) %}
{% set segments = 1 if stride == 1 else [128 // segsize, ((oa + segsize - 1) // segsize)] | min %}
{% set step = 2 if stride == 2 and width == 128 else 1 %}
{% set tile_step = segments * step * (2 if split and stride == 2 else 1) %}
{% set pieces = 1 if stride == 1 and ia <= 64 else 2 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.dsfull ~ '.L' %}
{% set dt = cr.dstail ~ '.L' %}
{% macro num(reg, n) %}
 SET {{ reg }} CR0 ;;
 {% for j in range(0,n|abs,255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ reg }} {{ [255,n|abs-j]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro load(slot, delta, tag) %}
 SET LR8 LR5 ;;
 {% if delta %}{{ 'INC' if delta > 0 else 'DEC' }} LR8 {{ delta|abs }} ;;{% endif %}
 BLT.S LR8 LR4 zero_{{ tag }} ;;
 BGE.S LR8 LR7 zero_{{ tag }} ;;
 LD.MULT.CYCLIC LR8 {{ cr.in0 }} {{ slot }} ; BEQ CR0 CR0 got_{{ tag }} ;;
 zero_{{ tag }}:
 LD.MULT.CYCLIC LR0 {{ cr.stage }} {{ slot }} ;;
 got_{{ tag }}:
{% endmacro %}
{% macro window(d, tag) %}
 {{ load('LR0',d-1,tag ~ 'p') }}
 {{ load('LR1',d,tag ~ 'c') }}
 {{ load('LR2',d+1,tag ~ 'n') }}
{% endmacro %}
{% macro stage_store(sd) %}
 ACTIVATE.QUANTIZE identity {{ sd }} {{ qi }} {{ cr.stage }} LR10 ; INC LR10 1 ;;
 {% if pieces == 2 %}
 LD.MULT.CYCLIC LR10 {{ cr.stage }} LR2 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ sd }} {{ qi }} {{ cr.stage }} LR10 ; INC LR10 1 ;;
 {% endif %}
{% endmacro %}

{{ num('LR0', 0) }}
{{ num('LR1', 128) }}
{{ num('LR2', 256) }}
{{ num('LR3', 0) }}
{{ num('LR4', 0) }}
{{ num('LR10', 0) }}
{{ num('LR12', cin - 1) }}
{{ num('LR14', tiles - 1) }}
MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stage }} LR0 ;;
stage_channel:
 SET LR5 LR4 ; SET LR6 CR0 ; ADD LR7 LR4 {{ cr.iplane }} ;;
stage_tile:
 {% for y in range(-1,2) %}
 {% for x in range(-1,2) %}
 {% set tag = (y+1) ~ '_' ~ (x+1) %}
 {% if segments > 1 %}
 SET LR15 CR0 ;;
 segment_{{ tag }}:
 {% elif not wide and y == -1 and x == -1 and stride == 2 %}
 SET LR15 CR0 ;;
 {% endif %}
 {% if wide or pieces == 2 or (y == -1 and x == -1) %}{{ window(y * (width // 128) if wide else 0,tag) }}{% endif %}
 {% set shift = x + (0 if wide else y * width) %}
 SET LR9 LR1 ;;
 {% if shift %}{{ 'INC' if shift > 0 else 'DEC' }} LR9 {{ shift|abs }} ;;{% endif %}
 {% if x %}
 {% set m = (1 if x > 0 else 0) %}
 {{ num('LR11',m) }}
 {% if split and stride == 1 %}
 ADD LR11 LR11 LR3 ;;
 ADD LR11 LR11 LR3 ;;
 {% elif split %}
 ADD LR11 LR11 LR15 ;;
 {% endif %}
 LD.MULT R0 LR11 {{ cr.masks }} ;;
 {% endif %}
 MULT.RC.{{ 'VV' if x else 'VE' }} LR9 {{ 'R0' if x else 'CR1' }} 0 LR0 {{ ds }} {{ qi }} ; {{ ('ACC.STRIDE ' ~ ([16, width]|max if not wide else 64) ~ ' on ' ~ ('off' if wide else 'on') ~ ' LR15') if stride == 2 else 'ACC.ADD.FIRST' }} ;;
 {% if segments > 1 %}
 INC LR15 {{ segsize // 32 }} ; INC LR5 {{ step }} ; BLT.S LR15 LR13 segment_{{ tag }} ;;
 DEC LR5 {{ segments*step }} ;;
 {% endif %}
 {% if oa % 128 and tiles > 1 %}
 BEQ LR6 LR14 stage_tail_{{ tag }} ;;
 {% endif %}
 {{ stage_store(dt if tiles == 1 else ds) }}
 {% if oa % 128 and tiles > 1 %}
 BEQ CR0 CR0 stage_next_{{ tag }} ;;
 stage_tail_{{ tag }}:
 {{ stage_store(dt) }}
 stage_next_{{ tag }}:
 {% endif %}
 {% endfor %}
 {% endfor %}
 {% if split and stride == 1 %}INC.MODP2 LR3 CR1 1 ;;{% endif %}
 INC LR5 {{ tile_step }} ; INC LR6 1 ; BLT.S LR6 LR14 stage_tile ;;
 SET LR4 LR7 ; DEC LR12 1 ; BLT.S CR0 LR12 stage_channel ;;
{% if pieces == 1 %}
MULT.RC.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.stage }} LR10 ; INC LR10 1 ;;
{% endif %}

{{ num('LR11', -1) }}
{% for j in range(5) %}
 LD.LUT {{ j }} {{ cr.lut }} LR11 ; INC LR11 1 ;;
{% endfor %}
{{ num('LR11', -1) }}
{{ num('LR12', -1) }}
{{ num('LR4', -1) }}
{{ num('LR5', 0) }}
{{ num('LR13', cout - 1) }}
{{ num('LR2', 0) }}
{{ num('LR15', cout // groups - 1) }}
output_channel:
 SET LR7 LR5 ; SET LR6 CR0 ;;
output_tile:
 SET LR8 LR4 ; SET {{ 'LR9' if pieces == 1 else 'LR13' }} LR7 ; SET LR10 CR0 ;;
 LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; SET LR3 CR0 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
 MULT.EE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; {% if pieces == 1 %}LD.MULT.CYCLIC LR9 {{ cr.stage }} LR0 ; INC LR9 1 ;{% endif %} ;;
 {% if cin // groups > 1 %}input_channel:{% endif %}
 {% for p in range(pieces) %}
 {% if pieces == 2 %}
 SET LR9 LR13 ;;
 LD.MULT.CYCLIC LR9 {{ cr.stage }} LR0 ; INC LR9 1 ;;
 {% endif %}
 LD.MULT R0 LR8 {{ cr.weights }} ; INC LR8 1 ; SUB LR3 LR0 CR1 ;;
 {% for t in range(9) %}
 MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1 ; LD.MULT.CYCLIC LR9 {{ cr.stage }} LR0 ; INC LR9 1 ; {% if pieces == 1 and loop.last and cin // groups > 1 %}INC LR10 1 ; BLT.S LR10 {{ cr.cend }} input_channel ;{% endif %} ;;
 {% if pieces == 2 %}
 MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; {% if not loop.last %}LD.MULT.CYCLIC LR9 {{ cr.stage }} LR0 ; INC LR9 1 ;{% endif %} ;;
 {% endif %}
 {% endfor %}
 {% endfor %}
 {% if pieces == 2 and cin // groups > 1 %}
 INC LR10 1 ; ADD LR13 LR13 {{ cr.spitch }} ; BLT.S LR10 {{ cr.cend }} input_channel ;;
 {% endif %}
 {% if oa % 128 and tiles > 1 %}
 BEQ LR6 LR14 output_tail ;;
 {% endif %}
 ACTIVATE.QUANTIZE generic {{ dt if tiles == 1 else ds }} {{ qo }} {{ cr.out0 }} LR11 ; INC LR11 1 ; INC LR7 {{ 9 * pieces }} ; INC LR6 1 ; BLT.S LR6 LR14 output_tile ;;
 {% if oa % 128 and tiles > 1 %}
 BEQ CR0 CR0 output_next ;;
 output_tail:
 ACTIVATE.QUANTIZE generic {{ dt }} {{ qo }} {{ cr.out0 }} LR11 ; INC LR11 1 ;;
 output_next:
 {% endif %}
 SET LR4 LR8 ; INC LR12 1 ; BGE.S LR12 {{ cr.outend }} finished ;;
 {% if groups > 1 %}
 INC LR2 1 ; BLT.S LR2 LR15 output_channel ;;
 SET LR2 CR0 ;;
 {{ num('LR3', cin // groups - 1) }}
group_advance:
 ADD LR5 LR5 {{ cr.spitch }} ; DEC LR3 1 ; BLT.S CR0 LR3 group_advance ;;
 {% endif %}
 BEQ CR0 CR0 output_channel ;;
finished:
 HALT ;;
