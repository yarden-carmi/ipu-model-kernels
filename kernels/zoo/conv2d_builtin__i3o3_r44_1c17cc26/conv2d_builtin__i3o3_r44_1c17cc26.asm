{% set chunks = (in0_d3 + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set last_input = cr.clean if in0_d3 % 128 else cr.in0 %}
{% set single = in0_d1 == 1 %}

{# Load the center and the in-bounds neighbor into the cyclic window. #}
{% macro products(c, y) %}
 SET LR10 LR9 ; SET LR7 CR0 ; SET LR6 LR2 ;;
 {% if y == 0 %}DEC LR10 {{ chunks }} ; {% elif y == 2 %}INC LR10 {{ chunks }} ; {% endif %}LD.MULT.CYCLIC LR10 {{ last_input if c == chunks-1 else cr.in0 }} LR2 ;;
 {% if chunks == 2 %}
 {{ 'INC' if c == 0 else 'DEC' }} LR10 1 ; LD.MULT.CYCLIC LR10 {{ last_input if c == 0 else cr.in0 }} {{ 'LR4' if c == 0 else 'LR0' }} ;;
 {% endif %}
 {% if y %}INC LR7 {{ 3*y-1 }} ; INC LR6 {{ 3*y-1 }} ;;{% else %}DEC LR7 1 ; DEC LR6 1 ;;{% endif %}
 {% for shift in ['LR1', 'LR2', 'LR3'] %}
 MULT.RC.VE {{ shift }} LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR7 1 ;;
 MULT.RC.VE {{ shift }} LR6 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR6 1 ;;
 {% endfor %}
{% endmacro %}

{% macro tile(c) %}
 {{ 'SET LR8 LR15 ;' if not single else '' }} SET LR9 LR12 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} {{ 'LR0' if c == 0 else 'LR4' }} ;;
 {% if chunks == 1 %}LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;{% endif %}
 {% if not single %}
 {% if c %}INC LR9 {{ c }} ;;{% endif %}
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
 {% endif %}
 {% if c and single %}INC LR9 {{ c }} ; {% endif %}MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST {{ '; BEQ LR13 CR0 skip_top_' ~ c if single else '' }} ;;
input_channel_{{ c }}:
 {% if not single %}BEQ LR13 CR0 skip_top_{{ c }} ;;{% endif %}
 {{ products(c, 0) }}
skip_top_{{ c }}:
 {{ products(c, 1) }}
 BEQ LR13 {{ cr.last_y }} skip_bottom_{{ c }} ;;
 {{ products(c, 2) }}
skip_bottom_{{ c }}:
 {% if not single %}
 ADD LR9 LR9 {{ cr.channel_pitch }} ; INC LR8 1 ;;
 BGE.S LR9 LR11 store_{{ c }} ;;
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; BEQ LR0 CR0 input_channel_{{ c }} ;;
store_{{ c }}:
 {% if bias %}
 SET LR7 CR0 ; SET LR6 LR2 ; LD.MULT R0 LR15 {{ cr.weights }} ; SET LR10 LR15 ;;
 INC LR7 9 ; INC LR6 9 ; INC LR10 1 ; LD.MULT R1 LR10 {{ cr.weights }} ;;
 {% endif %}
 {% endif %}
 {% if bias %}
 MULT.EE {{ 'LR8' if single else 'LR7' }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
 MULT.EE {{ 'LR11' if single else 'LR6' }} CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
 {% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail if c == chunks-1 else cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR14 CR0 ;;
 INC LR1 127 ; INC LR2 128 ; INC LR3 129 ;;
 INC LR4 255 ; DEC LR14 1 ;;
 INC LR4 1 ;;
 {% if in0_d3 % 128 %}
 SET LR9 CR0 ;;
 {% if chunks > 1 %}INC LR9 {{ chunks-1 }} ;;{% endif %}
clean_tail:
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR2 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.clean }} LR9 ;;
 INC LR9 {{ chunks }} ;;
 BLT.S LR9 LR5 clean_tail ;;
 {% endif %}

 {% if single and bias %}
 SET LR8 CR0 ; SET LR11 LR2 ;;
 INC LR8 9 ; INC LR11 9 ;;
 {% endif %}
 SET LR5 CR0 ;;
batch:
 SET LR15 CR1 ;;
output_channel:
 {% if single %}
 LD.MULT R0 LR15 {{ cr.weights }} ;;
 INC LR15 1 ; LD.MULT R1 LR15 {{ cr.weights }} ;;
 {% endif %}
 SET LR12 LR5 ; SET LR13 CR0 ;;
row:
 {% if not single %}ADD LR11 LR12 {{ cr.batch_pitch }} ;;{% endif %}
 {% for c in range(chunks) %}{{ tile(c) }}{% endfor %}
 INC LR12 {{ chunks }} ; INC LR13 1 ;;
 BGE.S {{ cr.last_y }} LR13 row ;;
 {% if single %}
 INC LR15 1 ; BLT.S LR15 {{ cr.last_weight }} output_channel ;;
 {% else %}
 SET LR15 LR8 ; BLT.S LR8 {{ cr.weight_rows }} output_channel ;;
 {% endif %}
 ADD LR5 LR5 {{ cr.batch_pitch }} ; INC LR14 1 ;;
 BLT.S LR14 {{ cr.out_rows }} more_batches ;;
 HALT ;;
more_batches:
 DEC LR14 1 ; BEQ LR0 CR0 batch ;;
