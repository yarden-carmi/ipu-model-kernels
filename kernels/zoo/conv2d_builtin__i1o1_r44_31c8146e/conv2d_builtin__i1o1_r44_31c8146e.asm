{% set iw = in0_d3 %}
{% set ih = in0_d2 %}
{% set fast = in0_d1 == 1 and out0_d1 <= 128 %}
{% macro move(r, n) %}
{% for k in range(0, n|abs, 255) %}
 {{ 'INC' if n > 0 else 'DEC' }} {{ r }} {{ [255, (n|abs)-k]|min }} ;;
{% endfor %}
{% endmacro %}
{% macro fetch(slot) %}LD.MULT.CYCLIC LR4 {{ cr.weights }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mul(slot, src, first=false) %}MULT.RC.VE {{ slot }} {{ src }} 0 LR8 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if first else 'ACC.ADD' }}{% endmacro %}
{% macro pair(src, first=false) %}
 {{ fetch('LR8') }} ;;
 {{ mul('LR8', src, first) }} ; {{ fetch('LR9') }} ;;
 {{ mul('LR9', src) }} ;;
{% endmacro %}
{% macro store(ds) %}ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1{% endmacro %}
{% macro interior_tap(t) %}
 LD.MULT R0 LR6 {{ cr.in0 }} ;;
 {{ mul('LR8', 'LR8') }} ; {{ fetch('LR9') }}{% if t < 8 %} ; INC LR6 {{ iw - 2 if t % 3 == 2 else 1 }}{% endif %} ;;
 {{ mul('LR9', 'LR8') }} ; {% if t < 8 %}{{ fetch('LR8') }}{% else %}{{ store(cr.tail) }}{% endif %} ;;
{% endmacro %}
{% macro edge_tap(y, x) %}
{% set name = 'tap_' ~ y ~ '_' ~ x %}
{% if x != 1 %}
 BEQ LR1 {{ 'CR0' if x == 0 else 'LR12' }} {{ name }}_skip ;;
{% endif %}
 SET LR6 LR2 ; SET LR7 CR0 ;;
 {{ move('LR6', (y - 1)*iw + x - 1) }}
 LD.MULT R0 LR6 {{ cr.in0 }} ;;
{{ name }}_channel:
 {{ pair('LR7') }}
{% if in0_d1 > 1 %}
 INC LR7 1 ;;
 BLT.S LR7 {{ cr.in0_d1 }} {{ name }}_channel ;;
{% endif %}
{% if x != 1 %}
 BEQ LR8 CR0 {{ name }}_end ;;
{{ name }}_skip:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
{{ name }}_end:
{% endif %}
{% endmacro %}
{% macro edge_row(y) %}
{% if y != 1 %}
 BEQ LR0 {{ 'CR0' if y == 0 else 'LR13' }} row_{{ y }}_skip ;;
{% endif %}
{% for x in range(3) %}{{ edge_tap(y, x) }}{% endfor %}
{% if y != 1 %}
 BEQ LR8 CR0 row_{{ y }}_end ;;
row_{{ y }}_skip:
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
 ADD LR4 LR4 {{ cr.tap_rows }} ;;
row_{{ y }}_end:
{% endif %}
{% endmacro %}

 SET LR8 CR0 ; SET LR9 CR0 ; SET LR2 CR0 ;;
 INC LR9 128 ; SET LR3 CR0 ; SET LR12 CR0 ;;
 SET LR13 CR0 ; DEC LR3 1 ;;
 {{ move('LR12', iw - 1) }}
 {{ move('LR13', ih - 1) }}
batch:
 SET LR0 CR0 ;;
oy:
 SET LR1 CR0 ;;
ox:
 SET LR4 CR0 ; SET LR5 CR0 ;;
 DEC LR4 1 ;;
{% if fast and iw >= 3 and ih >= 3 %}
 BEQ LR0 CR0 block ;;
 BEQ LR0 LR13 block ;;
 BEQ LR1 CR0 block ;;
 BEQ LR1 LR12 block ;;
 {{ fetch('LR8') }} ; SET LR6 LR2 ;;
 {{ mul('LR8', 'CR1', true) }} ; {{ fetch('LR9') }} ; DEC LR6 {{ iw + 1 }} ;;
 {{ mul('LR9', 'CR1') }} ; {{ fetch('LR8') }} ;;
{% for t in range(9) %}{{ interior_tap(t) }}{% endfor %}
 BEQ LR8 CR0 advance ;;
{% endif %}
block:
 {{ pair('CR1', true) }}
{% for y in range(3) %}{{ edge_row(y) }}{% endfor %}
{% if out0_d1 > 128 %}
 INC LR5 1 ;;
 BGE.S LR5 {{ cr.blocks }} last_block ;;
 {{ store(cr.full) }} ;;
 BEQ LR8 CR0 block ;;
last_block:
{% endif %}
 {{ store(cr.tail) }} ;;
advance:
 INC LR2 {{ stride }} ; INC LR1 {{ stride }} ;;
 BLT.S LR1 {{ cr.x_end }} ox ;;
 {{ move('LR2', stride * (iw - out0_d3)) }}
 INC LR0 {{ stride }} ;;
 BLT.S LR0 {{ cr.y_end }} oy ;;
 {{ move('LR2', (ih - out0_d2 * stride) * iw) }}
 DEC LR10 1 ;;
 BLT.S CR0 LR10 batch ;;
 HALT ;;
