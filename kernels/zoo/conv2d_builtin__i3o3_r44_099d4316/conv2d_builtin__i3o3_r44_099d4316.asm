{% set w = in0_d3 %}
{% set p = [in0_d2, [1, 128 // w]|max]|min %}
{% set pack = p if in0_d2 % p == 0 else 1 %}
{% set chunks = (w + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set last_input = cr.clean if w % 128 else cr.in0 %}

{# Stream the two spatial chunks through the cyclic register. Load the
   neighbor on the outward-facing tap and the next row on the last tap. #}
{% macro channel_loop(c, name, first, last) %}
input_channel_{{ c }}_{{ name }}:
 SET LR10 LR9 ; SET LR7 CR0 ; SET LR6 LR2 ;;
 {% if first == 0 %}DEC LR10 {{ chunks }} ; {% endif %}
 LD.MULT.CYCLIC LR10 {{ last_input if c == chunks-1 else cr.in0 }} LR2 ;;
 {% for y in range(first, last+1) %}
 {% for x in ([0, 1, 2] if c == 0 else [2, 1, 0]) %}
 {% set delta = (3*y+x if y == first else 3+x-(2 if c == 0 else 0)) if loop.first else (1 if c == 0 else -1) %}
 {% set step = ('INC' if delta > 0 else 'DEC') ~ ' ' %}
 MULT.RC.VE LR{{ x+1 }} LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
 {% if delta %}{{ step }}LR7 {{ delta|abs }} ; {% endif %}
 {% if loop.first and chunks == 2 %}
 {{ 'INC' if c == 0 else 'DEC' }} LR10 1 ; LD.MULT.CYCLIC LR10 {{ last_input if c == 0 else cr.in0 }} {{ 'LR4' if c == 0 else 'LR0' }} ;
 {% endif %};;
 MULT.RC.VE LR{{ x+1 }} LR6 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
 {% if delta %}{{ step }}LR6 {{ delta|abs }} ; {% endif %}
 {% if loop.first and y < last %}INC LR10 {{ 1 if chunks == 1 or c == 0 else 3 }} ; {% endif %}
 {% if loop.last and y < last %}LD.MULT.CYCLIC LR10 {{ last_input if c == chunks-1 else cr.in0 }} LR2 ; {% endif %};;
 {% endfor %}
 {% endfor %}
 ADD LR9 LR9 {{ cr.pitch }} ; INC LR8 1 ;;
 BGE.S LR9 {{ cr.input_rows }} store_{{ c }} ;;
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; BEQ LR0 CR0 input_channel_{{ c }}_{{ name }} ;;
{% endmacro %}

{% macro tile(c) %}
 SET LR8 LR15 ; SET LR9 LR12 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} {{ 'LR0' if c == 0 else 'LR4' }} ;;
 {% if chunks == 1 %}LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;{% endif %}
 {% if c %}INC LR9 {{ c }} ;;{% endif %}
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ;;
 MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 {% if in0_d2 == 1 %}
 {{ channel_loop(c, 'single', 1, 1) }}
 {% else %}
 BEQ LR13 CR0 input_channel_{{ c }}_top ;;
 BEQ LR13 {{ cr.last_y }} input_channel_{{ c }}_bottom ;;
 {{ channel_loop(c, 'middle', 0, 2) }}
 {{ channel_loop(c, 'top', 1, 2) }}
 {{ channel_loop(c, 'bottom', 0, 1) }}
 {% endif %}
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
