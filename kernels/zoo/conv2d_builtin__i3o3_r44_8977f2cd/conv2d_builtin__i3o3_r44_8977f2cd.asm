{% set w = in0_d3 %}
{% set p = [1, 128 // w]|max %}
{% set pack = p if in0_d2 % p == 0 else 1 %}
{% set chunks = (w + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}

{% macro offset(reg, n) %}
{% if n > 0 %}INC {{ reg }} {{ n }} ;;{% elif n < 0 %}DEC {{ reg }} {{ -n }} ;;{% endif %}
{% endmacro %}

{# The cyclic window contains previous/current/next physical rows.
   Off-image loads fall back to the current row; folded weights mask them. #}
{% macro window(tag, dy) %}
{% for dx in [-1, 0, 1] %}
{% set d = dy + dx %}
 SET LR13 LR9 ;;
 {{ offset('LR13', d) }}
 {% if d < 0 %}BGE.S LR13 CR0 {{ tag }}_{{ loop.index }} ;;
 SET LR13 LR9 ;;
 {{ tag }}_{{ loop.index }}:
 {% elif d > 0 %}BLT.S LR13 {{ cr.plane }} {{ tag }}_{{ loop.index }} ;;
 SET LR13 LR9 ;;
 {{ tag }}_{{ loop.index }}:
 {% endif %}
 ADD LR10 LR12 LR13 ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} {{ ['LR0', 'LR1', 'LR2'][loop.index0] }} ;;
{% endfor %}
{% endmacro %}

{% macro fetch() %}INC LR7 1 ; LD.MULT R0 LR7 {{ cr.weights }}{% endmacro %}

{% macro reduce(index, first=false, bias=false) %}
 {% for part in range(3) %}
 {% if bias %}MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }}
 {% else %}MULT.RC.VV {{ index }} R0 0 LR0 {{ full }} {{ qi }}{% endif %}
 ; {{ 'ACC.ADD.FIRST' if first and part == 0 else 'ACC.ADD' }}{% if part < 2 %} ; {{ fetch() }}{% endif %} ;;
 {% endfor %}
{% endmacro %}

{% macro chunk(c) %}
 {% set tag = 'c' ~ c %}
 SET LR3 CR0 ; SET LR8 CR0 ;;
 {{ offset('LR8', c) }}
{{ tag }}_channel:
 SET LR9 CR0 ;;
 {{ offset('LR9', c) }}
{{ tag }}_tile:
 SET LR7 LR6 ; SET LR12 CR0 ;;
 DEC LR7 1 ;;
 {{ fetch() }} ;;
 {{ reduce('LR0', true, true) }}
{{ tag }}_input_channel:
 {% if pack > 1 %}{{ window(tag ~ '_packed', 0) }}{% endif %}
 {% for y in [-1,0,1] %}
 {% if pack == 1 %}{{ window(tag ~ '_y' ~ loop.index, y * chunks) }}{% endif %}
 {% for x in [-1,0,1] %}
 SET LR11 LR1 ;;
 {{ offset('LR11', (y * w if pack > 1 else 0) + x) }}
 {{ fetch() }} ;;
 {{ reduce('LR11') }}
 {% endfor %}
 {% endfor %}
 ADD LR12 LR12 {{ cr.plane }} ;;
 BLT.S LR12 {{ cr.input_end }} {{ tag }}_input_channel ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ (cr.head if c == 0 else cr.tail) }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
 INC LR8 {{ chunks }} ; INC LR9 {{ chunks }} ;;
 BGE.S LR9 {{ cr.plane }} {{ tag }}_next_channel ;;
 BEQ LR9 LR15 {{ tag }}_next_variant ;;
 BEQ LR9 LR14 {{ tag }}_next_variant ;;
 BEQ LR0 CR0 {{ tag }}_tile ;;
{{ tag }}_next_variant:
 ADD LR6 LR7 CR1 ; BEQ LR0 CR0 {{ tag }}_tile ;;
{{ tag }}_next_channel:
 ADD LR6 LR7 CR1 ; INC LR3 1 ;;
 BLT.S LR3 {{ cr.out0_d1 }} {{ tag }}_channel ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 255 ; SET LR6 CR0 ;;
 INC LR2 1 ; SET LR14 {{ cr.plane }} ; SET LR15 CR0 ;;
 DEC LR14 {{ chunks }} ; INC LR15 {{ chunks }} ;;
 {% for c in range(chunks) %}
 {% if c %}INC LR14 1 ; INC LR15 1 ;;{% endif %}
 {{ chunk(c) }}
 {% endfor %}
 HALT ;;
