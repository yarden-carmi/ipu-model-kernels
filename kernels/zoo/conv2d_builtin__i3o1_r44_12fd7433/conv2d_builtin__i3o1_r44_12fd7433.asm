{% set iw = in0_d3 %}
{% set ih = in0_d2 %}
{% set chunks = (iw + 127) // 128 %}
{# Match the component counts in fold(): three corners use one stored vector. #}
{% set counts = [1,2,1,2,2,2,1,2,2] %}
{% macro adjust(r, n) %}{% if n %} ; {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ n|abs }}{% endif %}{% endmacro %}
{% macro fetch(slot) %}LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mul(slot, src, first=false) %}MULT.RC.VE {{ slot }} {{ src }} 0 LR8 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }}{% endmacro %}
{% macro store() %}ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1{% endmacro %}

{% macro span(tag, c, width, ys, ye) %}
 {# Pin the penultimate input row's final component so the streaming load
    slot can fetch the last input row in that component's multiply word. #}
 {% set cached = ye - ys == 3 %}
 {% set resident = ye - ys > 1 %}
 {% set pinned_tap = 3*(ye-2)+2 %}
 {% set pin = 1 + counts[:pinned_tap+1]|sum %}
 SET LR11 LR2 ; SET LR12 CR0 ; SET LR5 CR0 ;;
 INC LR12 {{ 1 + counts[:3*ys]|sum }} ; INC LR5 {{ width - 2 }}{{ adjust('LR11', c + (ys-1)*chunks) }} ;;
 SET LR6 LR11 ; SET LR4 CR0 ; SET LR1 CR0 ;;
 LD.MULT R0 LR6 {{ cr.in0 }} ;;
 {% if cached %}LD.MULT R1 LR6 {{ cr.in0 }} ; INC LR6 {{ chunks }} ;;{% endif %}
 {% if resident %}LD.MULT.CYCLIC LR4 {{ cr.weights }} LR9 ; INC LR4 {{ pin }} ;;{% endif %}
 SET LR4 LR12 ; SET LR6 LR11 ;;
{{ tag }}:
 {{ mul('LR14', 'CR1', true) }} ; SET LR7 LR1 ;;
 {{ mul('LR15', 'CR1') }} ; {{ fetch('LR8') }} ;;
 {% for y in range(ys, ye) %}
 {% for x in range(3) %}
 {% set tap = 3*y+x %}
 {% set pinned = y == ye-2 and x == 2 %}
 {% set last = y + 1 == ye and x == 2 %}
 {% for part in range(counts[tap]) %}
 {% set end = part+1 == counts[tap] %}
 {{ mul('LR9' if pinned and end else 'LR8', 'LR7') }}
 {%- if end and last %} ; SET LR6 LR11 ; SET LR4 LR12 ; LD.MULT R0 LR6 {{ cr.in0 }} ; {{ store() }} ; BLT.S LR1 LR5 {{ tag }}
 {%- elif end and pinned %} ; LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 {{ 2*chunks if cached else chunks }}
 {%- elif pinned or (x==1 and y==ye-2 and counts[tap+1]==1 and end) %} ; LD.MULT.CYCLIC LR4 {{ cr.weights }} LR8 ; INC LR4 2
 {%- else %} ; {{ fetch('LR8') }}{% endif %}
 {%- if part == 0 %}{% if x > 0 %} ; INC LR7 1{% elif cached and y == 1 %} ; ADD LR7 LR1 LR9{% elif y > ys %} ; SET LR7 LR1{% endif %}{% endif %}
 {%- if last and not end %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% endfor %}
{% endmacro %}

{% macro edge(px, ys, ye) %}
 {% set xs = 1 if px == 0 else 0 %}
 {% set xe = 2 if px == iw-1 else 3 %}
 {{ mul('LR14', 'CR1', true) }} ; SET LR6 LR2 ; SET LR4 CR0 ;;
 {{ mul('LR15', 'CR1') }} ; INC LR4 {{ 1 + counts[:3*ys+xs]|sum }}{{ adjust('LR6', (ys-1)*chunks+(px+xs-1)//128) }} ;;
 {% for y in range(ys, ye) %}
 {% for x in range(xs, xe) %}
 {% set ix = px+x-1 %}
 {% set load = x == xs or ix%128 == 0 %}
 {% set local = ix%128 %}
 {% set next_row = x + 1 == xe %}
 {% set delta = chunks+(px+xs-1)//128-ix//128 if next_row else (ix+1)//128-ix//128 %}
 {% if load %}LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR7 {{ 'LR9' if local > 64 else 'CR0' }} ;;{% endif %}
 {{ fetch('LR8') }}{{ adjust('LR7', (local-128 if local > 64 else local) if load else 1) }} ;;
 {% if counts[3*y+x] == 2 %}{{ mul('LR8', 'LR7') }} ; {{ fetch('LR9') }} ;;{% endif %}
 {{ mul('LR9' if counts[3*y+x]==2 else 'LR8', 'LR7') }}{{ adjust('LR6', delta) }}{% if next_row %}{{ adjust('LR4', counts[3*y+xe:3*(y+1)+xs]|sum) }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ store() }} ;;
{% endmacro %}
{% macro row(tag, ys, ye) %}
 {% for c in range(chunks) %}
 {% set width = [iw-c*128,128]|min %}
 {{ edge(c*128, ys, ye) }}
 {% if width > 2 %}{{ span(tag ~ '_' ~ c, c, width, ys, ye) }}{% endif %}
 {% if width > 1 %}{{ edge(c*128+width-1, ys, ye) }}{% endif %}
 {% endfor %}
{% endmacro %}

 SET LR8 CR0 ; SET LR9 CR0 ; SET LR2 CR0 ;;
 SET LR14 CR0 ; SET LR15 CR0 ; SET LR3 CR0 ;;
 INC LR9 128 ; INC LR14 255 ; INC LR15 255 ;;
 INC LR14 1 ; INC LR15 129 ; DEC LR3 1 ;;
 LD.MULT.CYCLIC LR8 {{ cr.weights }} LR14 ;;
 INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.weights }} LR15 ;;
 {% if iw == 1 or ih == 1 %}
 {# Degenerate axes never use off-image taps. Touch their constant rows
    without letting the values enter the accumulator. #}
 SET LR4 CR1 ;;
 {% for count in counts %}
 {% for part in range(count) %}{{ fetch('LR8') }} ;;{% endfor %}
 {% endfor %}
 {% endif %}
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
 {% if ih > 1 %}{{ row('bottom', 0, 2) }}
 INC LR2 {{ chunks }} ;;{% endif %}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
