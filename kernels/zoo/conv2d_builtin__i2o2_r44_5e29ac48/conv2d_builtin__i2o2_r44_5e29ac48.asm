{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}

{# Each scratch row contains only a subset of one input row, plus zeros. #}
{% macro sample(dy) %}
{% set start = 1 if dy == -1 else 0 %}
{% set end = [out0_d2, (in0_d2-1-dy)//stride+1]|min %}
{% set tag = dy+1 %}
 MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% if end > start %}
 SET LR4 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
 INC LR5 {{ end-start }} {% if start %}; ADDBI LRD10 {{ start }}{% endif %} {% if start*stride+dy %}; INC LR4 {{ start*stride+dy }}{% endif %} ;;
sample_{{ tag }}:
 MULT.EE LR4 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD12 LRD10 7 ;;
 INC LR4 {{ stride }} ; ADDBI LRD10 1 ; DEC LR5 1 ;;
 BNE LR5 CR0 sample_{{ tag }} ;;
{% endif %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.column }} LR2 ;;
 INC LR2 1 ;;
{% endmacro %}

{% macro mul(first=false, vector=false, third=false) %}
{% if vector %}
 MULT.RC.VE LR0 LR4 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
{% if not third %} MULT.RC.VE LR0 LR5 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;{% endif %}
{% else %}
 MULT.EE LR4 CR1 0 LR0 {{ ds }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }} ;;
{% if not third %} MULT.EE LR5 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;{% endif %}
{% endif %}
{% endmacro %}

{% macro taps(dx,third=false) %}
{% set tag = dx+1 %}
{% set label = 'skip_' ~ tag ~ ('_lo' if third else '') %}
 SET LR3 LR7 ; SET LR4 CR0 ; SET LR5 CR0 ;;
{% if dx == -1 %}
 BEQ LR6 CR0 {{ label }} ; DEC LR3 3 ;;
{% elif dx == 1 %}
 BEQ LR6 {{ cr.last_x }} {{ label }} ; INC LR3 3 ;;
{% endif %}
 INC LR4 {{ tag*3+1 }} ; INC LR5 {{ 128+tag*3+1 }} ;;
{% for tap in range(3) %}
 LD.MULT.CYCLIC LR3 {{ cr.column }} LR0 ;;
 {{ mul(vector=true,third=third) }}
{% if not loop.last %}
 INC LR3 1 ; INC LR4 1 ; INC LR5 1 ;;
{% endif %}
{% endfor %}
{% if dx != 0 %}{{ label }}:{% endif %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR12 CR0 ; SET LR13 CR0 ; SET LR10 CR0 ;;
prepare:
 LD.MULT R0 LR1 {{ cr.in0 }} ;;
{% for dy in range(-1,2) %}{{ sample(dy) }}{% endfor %}
 INC LR1 1 ;;
 BLT.S LR1 {{ cr.input_rows }} prepare ;;

 SET LR8 CR0 ; SET LR9 CR0 ;;
batch:
 SET LR1 CR0 ; SET LR2 CR0 ;;
channel:
 SET LR6 CR0 ; SET LR7 LR8 ;;
x_column:
 LD.MULT R0 LR1 {{ cr.weights }} ;;
 SET LR14 LR1 ;;
 INC LR14 1 ; LD.MULT R1 LR14 {{ cr.weights }} ;;
 SET LR4 CR0 ; SET LR5 CR0 ;;
 INC LR5 128 ;;
 {{ mul(first=true) }}
{% for dx in range(-1,2) %}{{ taps(dx) }}{% endfor %}
 INC LR14 1 ; LD.MULT R0 LR14 {{ cr.weights }} ; SET LR4 CR0 ;;
 {{ mul(third=true) }}
{% for dx in range(-1,2) %}{{ taps(dx,true) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
 INC LR9 1 ; INC LR6 {{ stride }} ; ADD LR7 LR7 {{ cr.scratch_step }} ;;
 BLT.S LR6 {{ cr.in0_d3 }} x_column ;;
 INC LR2 1 ; ADD LR8 LR8 {{ cr.scratch_plane }} ; INC LR1 3 ;;
 BLT.S LR2 {{ cr.out0_d1 }} channel ;;
 DEC LR15 1 ;;
 BNE LR15 CR0 batch ;;
 HALT ;;
