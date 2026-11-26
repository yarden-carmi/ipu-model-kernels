{% set width = in1_d3 %}
{% set area = in1_d2 * width %}
{% set tiles = (area + 127) // 128 %}
{% set block = 14 %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.ds128 ~ '.L' %}
{% macro num(r, n) %}
 SET {{ r }} CR0 ;;
 {% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro lut() %}
 {{ num('LR2', -1) }}
 {% for j in range(5) %}
 LD.LUT {{ j }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
 {% endfor %}
{% endmacro %}

{% if area <= 64 %}
{# Each packed input row feeds two successive windows: aligned and shifted
   by half a row. This gives each output every input channel, in a different order. #}
 {{ lut() }}
 {{ num('LR0', 0) }}
 {{ num('LR1', 128) }}
 {{ num('LR2', 64) }}
 {{ num('LR3', -1) }}
 {{ num('LR4', -1) }}
 {{ num('LR5', cin - 1) }}
 {{ num('LR6', (cin+1)//2 + 1) }}
 {{ num('LR10', (cin+1)//2 - 1) }}
 {{ num('LR11', 256) }}
 {{ num('LR12', 384) }}
 pack_channels:
 LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ; INC LR4 1 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; {% if cin % 2 %}BEQ LR4 LR5 pack_last ;{% endif %} ;;
 LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR1 ; INC LR4 1 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR3 ; INC LR3 1 ; BLT.S LR4 LR5 pack_channels ;;
 {% if cin % 2 %}
 BEQ CR0 CR0 packed_done ;;
 pack_last:
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR3 ; INC LR3 1 ;;
 packed_done:
 {% endif %}
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR3 ; INC LR3 1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR11 ;;
 LD.MULT.CYCLIC LR0 {{ cr.pad }} LR12 ;;
 {{ num('LR7', -1) }}
 {{ num('LR8', (cout+1)//2 - 1) }}
 {{ num('LR9', 0) }}
 {{ num('LR3', -1) }}
 pair:
 SUB LR13 LR0 CR1 ; SET LR14 CR0 ; SET LR15 LR1 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 1 ; SET LR2 LR0 ;;
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 {% for j in range(2) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{{ '.FIRST' if j == 0 else '' }} ; INC LR3 1 ; {% if j == 0 %}DEC LR2 {{63-width}} ;{% endif %} ;;
 {% endfor %}
 paired_channels:
 {% for phase in range(2) %}
 {% for t in range(9) %}
 {% set step = width-2 if t in [3,6] else (64-2*(width+1) if t == 0 else 1) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.RC.VV LR2 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1 ; INC LR2 {{ step }} ; {% if phase and t == 0 %}INC.MODP2 LR15 LR1 9 ;{% endif %} {% if phase and t == 8 %}INC LR14 1 ; BLT.S LR14 LR10 paired_channels ;{% endif %} ;;
 {% if not phase and t == 8 %}
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR15 ; INC LR13 1 ;;
 {% endif %}
 {% endfor %}
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR6 ; ADD LR12 LR6 CR1 ;;
 LD.MULT.CYCLIC LR6 {{ cr.pad }} LR0 ; INC LR12 2 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR12 ;;
 LD.MULT R1 LR3 {{ cr.weights }} ; INC LR3 1 ; ADD LR12 LR6 CR1 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR12 ;;
 MULT.VE LR1 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR12 ; INC LR12 1 ;;
 LD.MULT R0 LR12 {{ cr.pad }} ; DEC LR12 1 ;;
 LD.MULT R1 LR12 {{ cr.pad }} ; INC LR12 1 ;;
 LD.MULT.CYCLIC LR12 {{ cr.pad }} LR1 ; INC LR12 1 ; SET LR2 LR0 ;;
 {% for j in range(2) %}
 {% if j and cout % 2 %}BEQ LR9 LR8 finish ;;{% endif %}
 MULT.RC.VV LR2 {{ 'R0' if j == 0 else 'R1' }} 0 LR0 {{ ds }} {{ qo }} ; ACC.ADD.FIRST ; {% if j %}DEC LR2 64 ;{% endif %} ;;
 MULT.RC.VV LR2 {{ 'R0' if j == 0 else 'R1' }} 0 LR0 {{ ds }} {{ qo }} ; ACC.ADD ; ACTIVATE.QUANTIZE generic {{ cr.ds_tail }}.L {{ qo }} {{ cr.out0 }} LR7 ; INC LR7 1 ; INC LR2 128 ; {% if j %}INC LR9 1 ; BLT.S LR9 LR8 pair ;{% endif %} ;;
 {% endfor %}
 finish:
 HALT ;;
{% else %}
{# Stage one shifted, border-masked row per tap and input channel. #}
 {{ num('LR0', 0) }}
 {{ num('LR1', 128) }}
 {{ num('LR2', 256) }}
 {{ num('LR4', -1) }}
 {{ num('LR5', -1) }}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR4 ; INC LR4 1 ;;
 LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 LD.MULT R1 LR5 {{ cr.weights }} ; INC LR5 1 ;;
 {{ num('LR6', -1) }}
 {{ num('LR7', 0) }}
 {{ num('LR9', 0) }}
 {{ num('LR10', cin - 1) }}
 {{ num('LR11', tiles - 1) }}
 {% macro stage(suffix='', edge=-1) %}
 stage_tile{{ suffix }}:
 SET LR5 LR6 ; SET LR8 CR0 ;;
 stage_channel{{ suffix }}:
 {% if edge == 0 %}
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ;;
 {% elif edge == 1 %}
 DEC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ; INC LR5 1 ;;
  {% elif tiles > 1 %}
 BEQ LR7 CR0 top_guard ; DEC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ; INC LR5 1 ; BEQ CR0 CR0 center ;;
top_guard:
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ; INC LR5 1 ;;
 {% else %}
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ;;
 {% endif %}
 {% if edge >= 0 %}
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR1 ; INC LR5 1 ; SET LR3 LR1 ;;
 LD.MULT.CYCLIC {{ 'LR5 ' ~ cr.in1 if edge == 0 else 'LR4 ' ~ cr.pad }} LR2 ; INC LR5 1 ; DEC LR3 {{ width + 2 }} ;;
 {% else %}
 center:
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR1 ; INC LR5 1 ; SET LR3 LR1 ; BEQ LR7 LR11 bottom_guard ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR2 ; INC LR5 1 ; DEC LR3 {{ width + 2 }} ; BEQ CR0 CR0 stage_taps ;;
bottom_guard:
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR2 ; INC LR5 1 ; DEC LR3 {{ width + 2 }} ;;
 stage_taps:
 {% endif %}
 {% for t in range(9) %}
 {% set x = t % 3 %}
   MULT.RC.{{ 'VE' if x == 1 else 'VV' }} LR3 {{ ['R0','CR1','R1'][x] }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ; INC LR3 {{ width-2 if t and not x else 1 }} ;{% if loop.last and tiles == 2 %}INC LR8 1 ; BLT.S LR8 LR10 stage_channel{{ suffix }} ;{% endif %} ;;
 {% endfor %}
 {# The three source loads leave LR5 two rows ahead. For two-tile
    planes it is already at the next channel, so no correction is needed. #}
 {% if tiles != 2 %}
 ADD LR5 LR5 {{ cr.tiles }} ;;
  DEC LR5 2 ; INC LR8 1 ; BLT.S LR8 LR10 stage_channel ;;
  {% endif %}
  {% if edge == 0 %}
  INC LR6 1 ;;
  {% elif edge < 0 %}
  INC LR6 1 ; INC LR7 1 ; BLT.S LR7 LR11 stage_tile ;;
  {% endif %}
  {% endmacro %}
  {% if tiles == 2 %}
  {{ stage('_top', 0) }}
  {{ stage('_bottom', 1) }}
  {% else %}
  {{ stage() }}
  {% endif %}
  MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ;;
  SET LR6 LR9 ;;
  INC LR6 1 ;;

{# Prefetch the next spatial row in the same word as the leading MAC. #}
{% macro macs(n, again=false) %}
 LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ; SUB LR3 LR0 CR1 ;;
 {% for k in range(n) %}
 {% for t in range(9) %}
 {% set last = k == n-1 and t == 8 %}
 MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1 ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR0 ; INC LR1 1{% if again and last %} ; INC LR8 1 ; BLT.S LR8 LR9 coeff_block{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
 {{ lut() }}
 {{ num('LR4', 1) }}
 {{ num('LR14', -1) }}
 {{ num('LR9', cin // block - 1) }}
 {{ num('LR10', cout - 1) }}
output_channel:
 SET LR12 CR0 ; SET LR13 CR0 ;;
output_tile:
 SET LR2 LR4 ; SET LR1 LR12 ; SET LR8 CR0 ;;
 LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ; SET LR3 CR0 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R1 LR2 {{ cr.weights }} ; INC LR2 1 ;;
 INC LR3 128 ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR0 ; INC LR1 1 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 {% if cin >= block %}
coeff_block:
 {{ macs(block, true) }}
 {% endif %}
   {% if cin % block %}
   {{ macs(cin % block) }}
   {% endif %}
   ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR0 ; LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ;;
   LD.MULT.CYCLIC LR0 {{ cr.pad }} LR0 ;;
   MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR6 ;;
   SET LR7 LR0 ; LD.MULT R1 LR2 {{ cr.weights }} ; INC LR2 1 ;;
   LD.MULT.CYCLIC LR6 {{ cr.pad }} LR7 ; INC LR7 128 ; MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
   MULT.RC.VV LR7 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
   MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
   MULT.RC.VV LR7 R1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
 {% if area % 128 and tiles > 1 %}
 ;;
 BEQ LR13 LR11 tail_store ;;
 {% endif %}
 ACTIVATE.QUANTIZE generic {{ cr.ds_tail ~ '.L' if tiles == 1 else ds }} {{ qo }} {{ cr.out0 }} LR14 ; INC LR14 1 ; INC LR13 1 ; ADD LR12 LR12 {{ cr.tstep }} ; BLT.S LR13 LR11 output_tile ;;
 {% if area % 128 and tiles > 1 %}
 BEQ CR0 CR0 next_channel ;;
tail_store:
 ACTIVATE.QUANTIZE generic {{ cr.ds_tail }}.L {{ qo }} {{ cr.out0 }} LR14 ; INC LR14 1 ;;
next_channel:
 {% endif %}
 SET LR4 LR2 ; DEC LR10 1 ; BLT.S CR0 LR10 output_channel ;;
  HALT ;;
{% endif %}
