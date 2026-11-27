{% set w = in0_d3 %}
{% set p = [in0_d2, [1, 128 // w]|max]|min %}
{% set pack = p if in0_d2 % p == 0 else 1 %}
{% set chunks = (w + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set last_input = cr.clean if w % 128 else cr.in0 %}

{% macro products(c, y) %}
 {% if y != 2 %}SET LR10 LR9 ; SET LR7 CR0 ; SET LR6 LR2 ;;{% endif %}
 {% if y == 0 %}DEC LR10 {{ chunks }} ; {% elif y == 2 %}INC LR10 {{ chunks }} ; {% endif %}{% if y %}INC LR7 {{ 3*y-1 }} ; INC LR6 {{ 3*y-1 }} ; {% else %}DEC LR7 1 ; DEC LR6 1 ; {% endif %}LD.MULT.CYCLIC LR10 {{ last_input if c == chunks-1 else cr.in0 }} LR2 ;;
 {% if chunks == 2 %}
 {{ 'INC' if c == 0 else 'DEC' }} LR10 1 ; LD.MULT.CYCLIC LR10 {{ last_input if c == 0 else cr.in0 }} {{ 'LR4' if c == 0 else 'LR0' }} ;;
 {% endif %}
 {% for shift in ['LR1', 'LR2', 'LR3'] %}
 MULT.RC.VE {{ shift }} LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
 MULT.RC.VE {{ shift }} LR6 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR6 1 ;;
 {% endfor %}
{% endmacro %}

{% macro tile(c) %}
 SET LR8 LR15 ; SET LR9 LR12 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} {{ 'LR0' if c == 0 else 'LR4' }} ;;
 {% if chunks == 1 %}LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;{% endif %}
 {% if c %}INC LR9 {{ c }} ;;{% endif %}
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
 MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
input_channel_{{ c }}:
 BEQ LR13 CR0 skip_top_{{ c }} ;;
 {{ products(c, 0) }}
skip_top_{{ c }}:
 {{ products(c, 1) }}
 SET LR10 LR9 ; SET LR7 CR0 ; SET LR6 LR2 ; BEQ LR13 {{ cr.last_y }} skip_bottom_{{ c }} ;;
 {{ products(c, 2) }}
skip_bottom_{{ c }}:
 ADD LR9 LR9 {{ cr.pitch }} ; INC LR8 1 ;;
 BGE.S LR9 {{ cr.input_rows }} store_{{ c }} ;;
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; BEQ LR0 CR0 input_channel_{{ c }} ;;
store_{{ c }}:
 {% if bias %}
 SET LR7 CR0 ; SET LR6 LR2 ; LD.MULT R0 LR15 {{ cr.weights }} ; SET LR10 LR15 ;;
 INC LR7 9 ; INC LR6 9 ; INC LR10 1 ; LD.MULT R1 LR10 {{ cr.weights }} ;;
 MULT.EE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 MULT.EE LR6 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
 {% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail if c == chunks-1 else cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR14 CR0 ;;
 INC LR1 127 ; INC LR2 128 ; INC LR3 129 ;;
 INC LR4 255 ; DEC LR14 1 ;;
 INC LR4 1 ;;
 {% if pack > 1 %}
 SET LR9 CR0 ; SET LR10 CR0 ;;
unpack_row:
 SET LR11 LR2 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR2 ;;
unpack_item:
 MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.clean }} LR10 ;;
 INC LR11 {{ w }} ; INC LR10 1 ;;
 BLT.S LR11 {{ cr.unpack_end }} unpack_item ;;
 INC LR9 1 ;;
 BLT.S LR9 {{ cr.packed_rows }} unpack_row ;;
 {% elif w % 128 %}
 SET LR9 CR0 ;;
 {% if chunks > 1 %}INC LR9 {{ chunks-1 }} ;;{% endif %}
clean_tail:
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR2 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.clean }} LR9 ;;
 INC LR9 {{ chunks }} ;;
 BLT.S LR9 {{ cr.input_rows }} clean_tail ;;
 {% endif %}

 SET LR15 CR1 ;;
output_channel:
 SET LR12 CR0 ; SET LR13 CR0 ;;
row:
 {% for c in range(chunks) %}{{ tile(c) }}{% endfor %}
 INC LR12 {{ chunks }} ; INC LR13 1 ;;
 BGE.S {{ cr.last_y }} LR13 row ;;
 SET LR15 LR8 ; BLT.S LR8 {{ cr.weight_rows }} output_channel ;;
 HALT ;;
