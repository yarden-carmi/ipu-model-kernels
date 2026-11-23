{% set iw = in0_d3 %}
{% set ih = in0_d2 %}
{% set chunks = (iw + 127) // 128 %}
{% macro adjust(r, n) %}{% if n %} ; {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ n|abs }}{% endif %}{% endmacro %}
{% macro fetch(slot) %}LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mul(slot, src, first=false) %}MULT.RC.VE {{ slot }} {{ src }} 0 LR8 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }}{% endmacro %}
{% macro store() %}ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1{% endmacro %}

{# All three horizontal taps use one loaded input row. While multiplying
   each high/low weight, replace its slot with the corresponding next tap. #}
{% macro span(tag, c, width, ys, ye) %}
 SET LR11 LR2 ; SET LR12 CR0 ; SET LR5 CR0 ;;
 INC LR12 {{ 1 + 6 * ys }} ; INC LR5 {{ width - 2 }}{{ adjust('LR11', c + (ys-1)*chunks) }} ;;
 SET LR6 LR11 ; SET LR4 LR12 ; SET LR1 CR0 ;;
{{ tag }}:
 {{ mul('LR14', 'CR1', true) }} ; {{ fetch('LR8') }} ;;
 {{ mul('LR15', 'CR1') }} ; {{ fetch('LR9') }} ;;
 {% for y in range(ys, ye) %}
 LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR7 LR1 ;;
 {% for x in range(3) %}
 {% set last = y + 1 == ye and x == 2 %}
 {{ mul('LR8', 'LR7') }}{% if not last %} ; {{ fetch('LR8') }}{% else %} ; INC LR1 1{% endif %}{% if x > 0 %} ; INC LR7 1{% endif %} ;;
 {{ mul('LR9', 'LR7') }}{% if last %} ; SET LR6 LR11 ; SET LR4 LR12 ; {{ store() }} ; BLT.S LR1 LR5 {{ tag }}{% else %} ; {{ fetch('LR9') }}{% if x == 2 %} ; INC LR6 {{ chunks }}{% endif %}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}

{# The two sides of each chunk also cover the true zero-padded borders.
   The adjacent chunk is read only when the horizontal tap crosses into it. #}
{% macro edge(px, ys, ye) %}
 {% set xs = 1 if px == 0 else 0 %}
 {% set xe = 2 if px == iw-1 else 3 %}
 {{ mul('LR14', 'CR1', true) }} ; SET LR6 LR2 ; SET LR4 CR0 ;;
 {{ mul('LR15', 'CR1') }} ; INC LR4 {{ 1 + 2*(3*ys+xs) }}{{ adjust('LR6', (ys-1)*chunks+(px+xs-1)//128) }} ;;
 {% for y in range(ys, ye) %}
 {% for x in range(xs, xe) %}
 {% set ix = px+x-1 %}
 {% set load = x == xs or ix%128 == 0 %}
 {% set local = ix%128 %}
 {% set next_row = x + 1 == xe %}
 {% set delta = chunks+(px+xs-1)//128-ix//128 if next_row else (ix+1)//128-ix//128 %}
 {% if load %}
 LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR7 {{ 'LR9' if local > 64 else 'CR0' }} ;;
 {% endif %}
 {{ fetch('LR8') }}{{ adjust('LR7', (local-128 if local > 64 else local) if load else 1) }} ;;
 {{ mul('LR8', 'LR7') }} ; {{ fetch('LR9') }} ;;
 {{ mul('LR9', 'LR7') }}{{ adjust('LR6', delta) }}{% if next_row %}{{ adjust('LR4', 2*(3+xs-xe)) }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ store() }} ;;
{% endmacro %}
{% macro row(tag, ys, ye) %}
 {% for c in range(chunks) %}
 {% set width = [iw-c*128,128]|min %}
 {{ edge(c*128, ys, ye) }}
 {% if width > 2 %}
 {{ span(tag ~ '_' ~ c, c, width, ys, ye) }}
 {% endif %}
 {% if width > 1 %}
 {{ edge(c*128+width-1, ys, ye) }}
 {% endif %}
 {% endfor %}
{% endmacro %}

 SET LR8 CR0 ; SET LR9 CR0 ; SET LR2 CR0 ;;
 SET LR14 CR0 ; SET LR15 CR0 ; SET LR3 CR0 ;;
 INC LR9 128 ; INC LR14 255 ; INC LR15 255 ;;
 INC LR14 1 ; INC LR15 129 ; DEC LR3 1 ;;
 LD.MULT.CYCLIC LR8 {{ cr.weights }} LR14 ;;
 INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR15 ;;
 SET LR8 CR0 ;;
batch:
 {{ row('top', 1, 3 if ih > 1 else 2) }}
 INC LR2 {{ chunks }} ; SET LR0 CR1 ; SET LR13 CR0 ;;
 {% if ih > 2 %}
 INC LR13 {{ ih - 1 }} ;;
middle:
 {{ row('mid', 0, 3) }}
 INC LR2 {{ chunks }} ; INC LR0 1 ;;
 BLT.S LR0 LR13 middle ;;
 {% endif %}
 {% if ih > 1 %}
 {{ row('bottom', 0, 2) }}
 INC LR2 {{ chunks }} ;;
 {% endif %}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
