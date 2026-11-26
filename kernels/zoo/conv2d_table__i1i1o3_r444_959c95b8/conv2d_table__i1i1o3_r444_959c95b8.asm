{% set w = in1_d3 %}
{% set ic = (in1_d1 + 127) // 128 %}
{% set ds = cr.ds128 ~ '.L' %}
{% set qi = cr.qf_in1 ~ '.L' %}
{% set qw = cr.qf_weights ~ '.L' %}
{% macro adjust(r, n) %}
 {% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, n|abs-k]|min }} ;;
 {% endfor %}
{% endmacro %}
{% macro num(r, n) %}
 SET {{ r }} CR0 ;;
 {{ adjust(r, n) }}
{% endmacro %}
{% macro dot() %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ qi }} ; AGG.SUM LR2 {{ ds }}
{% endmacro %}
{% macro tap(t) %}
 {% if t < 3 %} BEQ LR7 LR0 skip{{ t }} ;; {% endif %}
 {% if t >= 6 %} BEQ LR7 LR11 skip{{ t }} ;; {% endif %}
 {% if t % 3 == 0 %} BEQ LR6 LR0 skip{{ t }} ;; {% endif %}
 {% if t % 3 == 2 %} BEQ LR6 LR10 skip{{ t }} ;; {% endif %}
 {% if ic > 1 %}
 {{ num('LR15', ic-1) }}
 chunk{{ t }}:
 {% endif %}
 LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR0 ; INC LR4 1 ;;
 {% for p in range(3) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1{% if p > 0 %} ; {{ dot() }}{% endif %} ;;
 {% endfor %}
 {{ dot() }}{% if ic > 1 %} ; DEC LR15 1 ; BLT.S CR0 LR15 chunk{{ t }}{% endif %} ;;
 {% if t != 4 %} after{{ t }}: {% endif %}
 {% if t in [2, 5] %} {{ adjust('LR4', (w-3)*ic) }} {% endif %}
{% endmacro %}

{{ num('LR0', 0) }}
{{ num('LR3', -1) }}
{% for j in range(5) %}
 LD.LUT {{ j }} {{ cr.lut }} LR3 ; INC LR3 1 ;;
{% endfor %}
{{ num('LR9', -(w+1)*ic-1) }}
{{ num('LR10', out0_d3-1) }}
{{ num('LR11', out0_d2-1) }}
{{ num('LR14', -1) }}
SET LR7 CR0 ;;
row:
 {{ num('LR8', -1) }}
 SET LR1 {{ cr.tiles }} ;;
 DEC LR1 1 ;;
tile:
 SET LR3 LR8 ; SET LR2 CR0 ;;
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR8 2 ; INC LR3 1 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD.FIRST ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qw }} ; ACC.ADD ;;
 {{ num('LR13', 128 // out0_d3 - 1) }}
channel:
 SET LR5 LR9 ; SET LR6 CR0 ;;
pixel:
 SET LR4 LR5 ; SET LR3 LR8 ;;
 {% for t in range(9) %}
 {{ tap(t) }}
 {% endfor %}
 INC LR2 1 ; INC LR5 {{ ic }} ; INC LR6 1 ; BLT.S LR6 LR10 pixel ;;
 ADD LR8 LR8 {{ cr.wblock }} ; DEC LR13 1 ; BLT.S CR0 LR13 channel ;;
 ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ; DEC LR1 1 ; BLT.S CR0 LR1 tile ;;
 ADD LR9 LR9 {{ cr.rowstep }} ; INC LR7 1 ; BLT.S LR7 LR11 row ;;
 HALT ;;

{% for t in range(9) if t != 4 %}
 skip{{ t }}:
 INC LR4 {{ ic }} ; INC LR3 {{ 3*ic }} ; BEQ LR0 LR0 after{{ t }} ;;
{% endfor %}
