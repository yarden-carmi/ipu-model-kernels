{% set width = in1_d3 %}
{% set area = in1_d2 * width %}
{% set tiles = (area + 127) // 128 %}
{% set block = 7 if area >= 512 else 14 %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.ds128 ~ '.L' %}
{% set tail = cr.ds_tail ~ '.L' %}
{% macro num(r, n) %}
 SET {{ r }} CR0 ;;
 {% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255,n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro lut() %}
 {{ num('LR2', -1) }}
 {% for j in range(5) %}
 LD.LUT {{ j }} {{ cr.lut }} LR2 ; INC LR2 1 ;;
 {% endfor %}
{% endmacro %}
{% macro readw(r, p) %}LD.MULT {{ r }} {{ p }} {{ cr.weights }} ; INC {{ p }} 1{% endmacro %}

{% if area <= 64 %}
{# Duplicate the spatial plane and compute two output channels at once. #}
 {{ lut() }}
 {{ num('LR0', 0) }}
 {{ num('LR1', 128) }}
 {{ num('LR2', 448) }}
 {{ num('LR3', -1) }}
 {{ readw('R0','LR3') }} ;;
 {{ readw('R1','LR3') }} ;;
 {{ num('LR4', -1) }}
 {{ num('LR5', cin - 1) }}
duplicate:
 LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ; INC LR4 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR2 R1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR4 ; BLT.S LR4 LR5 duplicate ;;
 {{ num('LR6', cin) }}
 {{ num('LR7', -1) }}
 {{ num('LR8', (cout+1)//2 - 1) }}
 {{ num('LR9', 0) }}
 {{ readw('R0','LR3') }} ;;
pair:
 {{ num('LR13', -1) }}
 SET LR14 CR0 ;;
 {% for j in range(2) %}
 {{ readw('R0','LR3') }} ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{{ '.FIRST' if j == 0 else '' }} ;;
 {% endfor %}
channel:
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR0 ; INC LR13 1 ; SET LR2 LR0 ;;
 LD.MULT.CYCLIC LR13 {{ cr.pad }} LR1 ; INC LR2 {{ 63-width }} ;;
 {% for t in range(9) %}
 {% for j in range(2) %}
 {{ readw('R0','LR3') }} ; MULT.RC.VV LR2 R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{% if j == 0 and t %} ; INC LR2 {{ width-2 if t % 3 == 0 else 1 }}{% endif %}{% if t == 8 and j == 1 %} ; INC LR14 1 ; BLT.S LR14 LR5 channel{% endif %} ;;
 {% endfor %}
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.pad }} LR6 ;;
 LD.MULT.CYCLIC LR6 {{ cr.pad }} LR0 ;;
 {% for j in range(2) %}
 {% if j == 1 %}
 {% if cout % 2 %} BEQ LR9 LR8 finish ;; {% endif %}
 {{ num('LR2', 64) }}
 {% endif %}
 {% if j == 0 %} {{ readw('R1','LR3') }} ;; {% endif %}
 MULT.RC.VV {{ 'LR0 R0' if j == 0 else 'LR2 R1' }} 0 LR0 {{ ds }} {{ qo }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE generic {{ tail }} {{ qo }} {{ cr.out0 }} LR7 ; INC LR7 1{% if j == 0 %} ; {{ readw('R0','LR3') }}{% else %} ; INC LR9 1 ; BLT.S LR9 LR8 pair{% endif %} ;;
 {% endfor %}
finish:
 HALT ;;
{% else %}
{# Stage border-masked stencil rows once for all output channels. #}
 {{ num('LR0', 0) }}
 {{ num('LR1', 128) }}
 {{ num('LR2', 256) }}
 {{ num('LR4', -1) }}
 {{ num('LR5', -1) }}
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR4 ; INC LR4 1 ;;
 {{ readw('R0','LR5') }} ;;
 {{ readw('R1','LR5') }} ;;
 {{ num('LR6', -1) }}
 {{ num('LR7', 0) }}
 {{ num('LR9', 0) }}
 {{ num('LR10', cin - 1) }}
 {{ num('LR11', tiles - 1) }}
stage_tile:
 SET LR5 LR6 ; SET LR8 CR0 ;;
stage_channel:
 {% if tiles > 1 %}
 BEQ LR7 CR0 top_guard ; DEC LR5 1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR0 ; INC LR5 1 ; BEQ CR0 CR0 center ;;
top_guard:
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ; INC LR5 1 ;;
 {% else %}
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR0 ;;
 {% endif %}
center:
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR1 ; INC LR5 1 ; BEQ LR7 LR11 bottom_guard ;;
 LD.MULT.CYCLIC LR5 {{ cr.in1 }} LR2 ; INC LR5 1 ; BEQ CR0 CR0 stage_taps ;;
bottom_guard:
 LD.MULT.CYCLIC LR4 {{ cr.pad }} LR2 ; INC LR5 1 ;;
stage_taps:
 SET LR3 LR1 ;;
 DEC LR3 {{ width + 2 }} ;;
 {% for t in range(9) %}
 {% set x = t % 3 %}
 MULT.RC.{{ 'VE' if x == 1 else 'VV' }} LR3 {{ ['R0','CR1','R1'][x] }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ; INC LR3 {{ width-2 if t and not x else 1 }} ;;
 {% endfor %}
 ADD LR5 LR5 {{ cr.tiles }} ;;
 DEC LR5 2 ; INC LR8 1 ; BLT.S LR8 LR10 stage_channel ;;
 INC LR6 1 ; INC LR7 1 ; BLT.S LR7 LR11 stage_tile ;;
 MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.pad }} LR9 ; INC LR9 1 ;;

{% macro macs(n, again=false) %}
 {{ readw('R0','LR2') }} ; SET LR3 CR0 ; SET LR15 CR0 ;;
 {{ readw('R1','LR2') }} ; DEC LR3 1 ; INC LR15 127 ;;
 {% for k in range(n) %}
 {% for t in range(9) %}
 {% if area >= 512 or t % 2 or t == 4 or (t == 6 and k < 12) %}
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
 {{ readw('R0','LR2') }} ; SET LR3 CR0 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; {{ readw('R1','LR2') }} ;;
 INC LR3 128 ; LD.MULT.CYCLIC LR1 {{ cr.pad }} LR0 ; INC LR1 1 ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 {% if cin >= block %}
coeff_block:
 {{ macs(block, true) }}
 {% endif %}
 {% if cin % block %}
 {{ macs(cin % block) }}
 {% endif %}
 {% if area % 128 and tiles > 1 %} BEQ LR13 LR11 tail_store ;; {% endif %}
 ACTIVATE.QUANTIZE generic {{ tail if tiles == 1 else ds }} {{ qo }} {{ cr.out0 }} LR14 ; INC LR14 1 ; INC LR13 1 ; ADD LR12 LR12 {{ cr.tstep }} ; BLT.S LR13 LR11 output_tile ;;
 {% if area % 128 and tiles > 1 %}
 BEQ CR0 CR0 next_channel ;;
tail_store:
 ACTIVATE.QUANTIZE generic {{ tail }} {{ qo }} {{ cr.out0 }} LR14 ; INC LR14 1 ;;
next_channel:
 {% endif %}
 SET LR4 LR2 ; DEC LR10 1 ; BLT.S CR0 LR10 output_channel ;;
 HALT ;;
{% endif %}
