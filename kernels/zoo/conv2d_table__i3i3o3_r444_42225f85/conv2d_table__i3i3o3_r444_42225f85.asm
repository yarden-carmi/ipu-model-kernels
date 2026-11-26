{% set width = in1_d3 %}
{% set area = in1_d2 * width %}
{% set tiles = (area + 127) // 128 %}
{% set block = 12 if area >= 512 else 14 %}
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
{# Duplicate the input plane so two output channels share each spatial MAC. #}
 {{ lut() }}
 {{ num('LR0', 0) }}
 {{ num('LR1', 128) }}
 {{ num('LR2', 448) }}
 {{ num('LR3', -1) }}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 LD.MULT R1 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 {{ num('LR4', -1) }}
 {{ num('LR5', cin - 1) }}
duplicate:
 LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR2 R1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR4 ; BLT.S LR4 LR5 duplicate ;;
 {{ num('LR6', cin) }}
 {# Initialize the cyclic neighbors accessed only by masked border lanes. #}
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR1 ; {{ 'SET LR2 CR0' }} ;;
 INC LR2 255 ;;
 INC LR2 129 ;;
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR2 ;;
 {{ num('LR1', -width-1) }}
 {{ num('LR7', -1) }}
 {{ num('LR8', (cout+1)//2 - 1) }}
 {{ num('LR9', 0) }}
 {{ num('LR11', 128) }}
 {{ num('LR10', (cin // 4 - 1) * 4) }}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
pair:
 SET LR13 CR0 ; SET LR14 CR0 ;;
 DEC LR13 1 ;;
 {% for j in range(2) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{{ '.FIRST' if j == 0 else '' }} ; INC LR3 1 ;;
 {% endfor %}
 {% macro pair_channel(branch=false) %}
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 1 ; SET LR2 LR1 ;;
 {% for t in range(9) %}
 {% for j in range(2 if t == 3 else 1) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; MULT.RC.VV LR2 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1{% if j == 0 and t %} ; INC LR2 {{ width-2 if t % 3 == 0 else 1 }}{% endif %}{% if branch and t == 8 %} ; INC LR14 4 ; BLT.S LR14 LR10 channel{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% endmacro %}
 {% if cin >= 4 %}
channel:
 {% for c in range(4) %}
 {{ pair_channel(loop.last) }}
 {% endfor %}
 {% endif %}
 {% for c in range(cin % 4) %}
 {{ pair_channel() }}
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR6 ;;
 LD.MULT.CYCLIC LR6 {{ cr.pad }} LR0 ; SET LR12 LR6 ;;
 INC LR12 3 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR12 ;;
 LD.MULT R1 LR3 {{ cr.weights }} ; INC LR3 1 ; SET LR12 LR6 ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR12 ; INC LR12 1 ;;
 MULT.VE LR11 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR12 ; INC LR12 1 ;;
 DEC LR12 1 ; LD.MULT R0 LR12 {{ cr.pad }} ;;
 INC LR12 1 ; LD.MULT R1 LR12 {{ cr.pad }} ;;
 {% for j in range(2) %}
 {% if j == 1 %}
 {% if cout % 2 %} BEQ LR9 LR8 finish ;; {% endif %}
 {{ num('LR2', 64) }}
 {% endif %}
 {% set pos = 'LR0' if j == 0 else 'LR2' %}
 {% set reg = 'R0' if j == 0 else 'R1' %}
 {% if j == 0 %}
 INC LR12 1 ; LD.MULT.CYCLIC LR12 {{ cr.pad }} LR11 ;;
 {% endif %}
 MULT.RC.VV {{ pos }} {{ reg }} 0 LR0 {{ ds }} {{ qo }} ; ACC.ADD.FIRST ; ADD LR12 {{ pos }} LR11 ;;
 MULT.RC.VV LR12 {{ reg }} 0 LR0 {{ ds }} {{ qo }} ; ACC.ADD ; ACTIVATE.QUANTIZE generic {{ cr.ds_tail }}.L {{ qo }} {{ cr.out0 }} LR7 ; INC LR7 1{% if j == 0 %} ; LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1{% else %} ; INC LR9 1 ; BLT.S LR9 LR8 pair{% endif %} ;;
 {% endfor %}
finish:
 HALT ;;
{% else %}
{# Stage the nine spatially shifted, border-masked inputs for each tile/channel. #}
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
 {% if edge == 0 or tiles == 1 %}
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ;;
 {% elif edge == 1 %}
 DEC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ; INC LR5 1 ;;
 {% else %}
 BEQ LR7 CR0 top_guard ; DEC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ; INC LR5 1 ; BEQ CR0 CR0 center ;;
top_guard:
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ; INC LR5 1 ;;
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
 MULT.RC.{{ 'VE' if x == 1 else 'VV' }} LR3 {{ ['R0','CR1','R1'][x] }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ; INC LR3 {{ width-2 if t and not x else 1 }}{% if loop.last and tiles == 2 %} ; INC LR8 1 ; BLT.S LR8 LR10 stage_channel{{ suffix }}{% endif %} ;;
 {% endfor %}
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

 {# Prefetch the next spatial row alongside each leading coefficient MAC. #}
 {% macro macs(n, again=false) %}
 LD.MULT R0 LR2 {{ cr.weights }} ; INC LR2 1 ; SET LR3 CR0 ; SET LR15 CR0 ;;
 {% if area < 512 %}
 LD.MULT R1 LR2 {{ cr.weights }} ; INC LR2 1 ; DEC LR3 1 ; INC LR15 127 ;;
 {% else %}
 DEC LR3 1 ;;
 {% endif %}
 {% for k in range(n) %}
 {% for t in range(9) %}
{% if t == 3 and area < 512 %}
 MULT.RC.VE LR0 LR15 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR15 1 ;;
 {% endif %}
 MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR3 1 ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR0 ; INC LR1 1{% if again and k == n-1 and t == 8 %} ; INC LR8 1 ; BLT.S LR8 LR9 coeff_block{% endif %} ;;
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
