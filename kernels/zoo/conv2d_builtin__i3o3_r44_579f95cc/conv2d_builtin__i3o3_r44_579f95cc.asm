{% set chunks = (in0_d3 + 127) // 128 %}
{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro next_weight() %}INC LR9 1 ; LD.MULT R0 LR9 {{ cr.weights }}{% endmacro %}
{% macro bias_parts() %}
 {{ next_weight() }} ;;
 {% for p in range(3) %}
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if p == 0 else 'ACC.ADD' }}{% if p < 2 %} ; {{ next_weight() }}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro products(c) %}
 {{ next_weight() }} ;;
 {% for shift in ['LR1', 'LR2', 'LR3'] %}
 {% for p in range(3) %}
 MULT.RC.VV {{ shift }} R0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD{% if not (shift == 'LR3' and p == 2) %} ; {{ next_weight() }}{% else %} ; INC LR11 {{ chunks }} ; DEC LR12 1 ; BNE LR12 CR1 input_channel_{{ c }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro store(size) %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ size }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
{% endmacro %}

{% macro tile(c) %}
 SET LR14 LR5 ; SUB LR11 LR10 {{ cr.row_stride }} ;;
 DEC LR14 1 ;;
 {{ bias_parts() }}
vertical_{{ c }}:
 BLT.S LR14 CR0 skip_vertical_{{ c }} ;;
 BGE.S LR14 {{ cr.in0_d2 }} skip_vertical_{{ c }} ;;
 SET LR12 {{ cr.in0_d1 }} ;;
input_channel_{{ c }}:
 LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR2 ;;
 {% if chunks > 1 %}
 {{ 'ADD LR13 LR11 CR1 ; LD.MULT.CYCLIC LR13 ' ~ cr.in0 ~ ' LR4' if c == 0 else 'SUB LR13 LR11 CR1 ; LD.MULT.CYCLIC LR13 ' ~ cr.in0 ~ ' LR0' }} ;;
 {% endif %}
 {{ products(c) }}
 BEQ LR0 CR0 next_vertical_{{ c }} ;;
skip_vertical_{{ c }}:
 ADD LR9 LR9 {{ cr.tap_rows }} ; ADD LR11 LR11 {{ cr.row_stride }} ;;
next_vertical_{{ c }}:
 INC LR14 1 ;;
 BLT.S LR14 LR6 vertical_{{ c }} ;;
 {{ store(cr.tail if c == chunks - 1 else cr.full) }}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR8 CR0 ; SET LR10 CR0 ; INC LR1 127 ;;
 INC LR2 128 ; INC LR3 129 ; INC LR4 255 ;;
 INC LR4 1 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;
row:
 SET LR7 CR0 ; SET LR15 CR0 ; SET LR6 LR5 ;;
 INC LR6 2 ;;
channel:
 SET LR9 LR15 ;;
 {{ tile(0) }}
 {% if chunks > 1 %}
 INC LR8 1 ; INC LR10 1 ;;
 {{ tile(1) }}
 {% endif %}
 INC LR8 1 ; INC LR7 1 ; ADD LR15 LR15 {{ cr.channel_rows }} ;;
 {% if chunks > 1 %}DEC LR10 {{ chunks - 1 }} ;;{% endif %}
 BLT.S LR7 {{ cr.out0_d1 }} channel ;;
 ADD LR10 LR10 {{ cr.row_stride }} ; INC LR5 1 ;;
 BLT.S LR5 {{ cr.in0_d2 }} row ;;
 SET LR5 CR0 ;;
 BLT.S LR8 {{ cr.out_rows }} row ;;
 HALT ;;
