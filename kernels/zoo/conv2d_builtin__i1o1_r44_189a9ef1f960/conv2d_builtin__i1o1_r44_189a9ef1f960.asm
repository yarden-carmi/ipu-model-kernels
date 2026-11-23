{% set parts = 1 %}
{% macro product(i, more=true) %}
{% set src = 'LR11' if i % 2 == 0 else 'LR12' %}
{% set next = 'LR12' if i % 2 == 0 else 'LR11' %}
{% for p in range(parts) %}
 MULT.RC.VE LR15 {{ src }} 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD {% if more or p+1 < parts %}; INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15{% endif %}{% if p+1 == parts and more %} ; INC {{ next }} 2{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro tap(dx,dy) %}
{% set name = 'tap_' ~ (dy+1) ~ (dx+1) %}
{% if dy == -1 %}
 BEQ LR0 CR0 {{ name }}_skip ;;
{% elif dy == 1 %}
 BEQ LR0 {{ cr.last_y }} {{ name }}_skip ;;
{% endif %}
{% if dx == -1 %}
 BEQ LR2 CR0 {{ name }}_skip ;;
{% elif dx == 1 %}
 BEQ LR2 {{ cr.last_x }} {{ name }}_skip ;;
{% endif %}
 SET LR9 LR1 ; SET LR11 CR0 ; SET LR12 CR0 ;;
{% set offset = dy*w+dx %}
 LD.MULT R0 LR9 {{ cr.in0 }} ; DEC LR12 1 {% if offset %}; {{ 'INC' if offset > 0 else 'DEC' }} LR9 {{ offset|abs }}{% endif %} ;;
 INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
{% if cin > 24 %}
{{ name }}:
{% for i in range(24) %}
 {{ product(i) }}
{% endfor %}
 BLT.S LR11 {{ cr.panel_end }} {{ name }} ;;
{% endif %}
{% for i in range((cin-1)%24) %}
 {{ product(i) }}
{% endfor %}
 {{ product(cin-1, false) }}
{% if dx or dy %}
 BEQ LR15 CR0 {{ name }}_end ;;
{{ name }}_skip:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
{{ name }}_end:
{% endif %}
{% endmacro %}
 SET LR15 CR0 ; SET LR13 CR0 ; SET LR1 CR0 ;;
batch:
 SET LR0 CR0 ;;
oy:
 SET LR2 CR0 ;;
ox:
 SET LR3 CR0 ; SET LR4 CR0 ;;
 DEC LR4 1 ;;
block:
{% for p in range(parts) %}
 INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR15 ;;
 MULT.RC.VE LR15 CR1 0 LR15 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if p == 0 else 'ACC.ADD' }} ;;
{% endfor %}
{% for dy in range(-1,2) %}
{% for dx in range(-1,2) %}
 {{ tap(dx,dy) }}
{% endfor %}
{% endfor %}
{% if cout > 128 %}
 INC LR3 1 ;;
 BGE.S LR3 {{ cr.blocks }} last_block ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; BEQ LR15 CR0 block ;;
last_block:
{% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
 INC LR13 1 ; INC LR1 {{ stride }} ; INC LR2 {{ stride }} ;;
 BLT.S LR2 {{ cr.x_end }} ox ;;
{% for unused in range(stride-1) %}
 INC LR1 {{ w }} ;;
{% endfor %}
{% if stride == 2 and w % 2 %}
 DEC LR1 1 ;;
{% endif %}
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
{% if stride == 2 and h % 2 %}
 DEC LR1 {{ w }} ;;
{% endif %}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
