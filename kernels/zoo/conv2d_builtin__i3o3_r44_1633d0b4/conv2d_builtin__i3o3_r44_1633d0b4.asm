{% set chunks = (in0_d3 + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set last_input = cr.clean if in0_d3 % 128 else cr.in0 %}

{# Start with the shift toward the zero slot, so the neighboring chunk
   can load in parallel with that product. LR writes feed MULT immediately. #}
{% macro products(c, y) %}
 SET LR10 LR9 ; SET LR7 CR0 ; SET LR6 LR2 ;;
 {% if y == 0 %}DEC LR10 {{ chunks }} ; {% elif y == 2 %}INC LR10 {{ chunks }} ; {% endif %}LD.MULT.CYCLIC LR10 {{ last_input if c == chunks-1 else cr.in0 }} LR2 ;;
 {% for x in ([0, 1, 2] if c == 0 else [2, 1, 0]) %}
 {% set delta = 3*y+x if loop.first else (1 if c == 0 else -1) %}
 {% set advance = 'INC' if delta > 0 else 'DEC' %}
 MULT.RC.VE LR{{ x+1 }} LR7 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;
 {% if delta %}{{ advance }} LR7 {{ delta|abs }} ; {% endif %}
 {% if loop.first and chunks == 2 %}{{ 'INC' if c == 0 else 'DEC' }} LR10 1 ; LD.MULT.CYCLIC LR10 {{ last_input if c == 0 else cr.in0 }} {{ 'LR4' if c == 0 else 'LR0' }} ; {% endif %};;
 MULT.RC.VE LR{{ x+1 }} LR6 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; {% if delta %}{{ advance }} LR6 {{ delta|abs }} ; {% endif %};;
 {% endfor %}
{% endmacro %}

{% macro tile(c) %}
 SET LR8 LR15 ; SET LR9 LR12 ; LD.MULT.CYCLIC LR0 {{ cr.weights }} {{ 'LR0' if c == 0 else 'LR4' }} ;;
 {% if chunks == 1 %}LD.MULT.CYCLIC LR0 {{ cr.weights }} LR4 ;;{% endif %}
 {% if c %}INC LR9 {{ c }} ;;{% endif %}
 LD.MULT R0 LR8 {{ cr.weights }} ; SET LR7 CR0 ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; INC LR7 9 ; SET LR6 LR2 ;;
 INC LR6 9 ; MULT.EE LR7 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.EE LR6 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ;;
input_channel_{{ c }}:
 BEQ LR13 CR0 skip_top_{{ c }} ;;
 {{ products(c, 0) }}
skip_top_{{ c }}:
 {{ products(c, 1) }}
 BEQ LR13 {{ cr.last_y }} skip_bottom_{{ c }} ;;
 {{ products(c, 2) }}
skip_bottom_{{ c }}:
 ADD LR9 LR9 {{ cr.channel_pitch }} ; INC LR8 1 ;;
 BGE.S LR9 LR11 store_{{ c }} ;;
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 LD.MULT R1 LR8 {{ cr.weights }} ; INC LR8 1 ; BEQ LR0 CR0 input_channel_{{ c }} ;;
store_{{ c }}:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail if c == chunks-1 else cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; INC LR14 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR4 CR0 ; SET LR12 CR0 ;;
 SET LR13 CR0 ; SET LR14 CR0 ; INC LR1 127 ;;
 INC LR2 128 ; INC LR3 129 ; INC LR4 255 ;;
 INC LR4 1 ; DEC LR14 1 ;;
 {% if in0_d3 % 128 %}
 {# Sanitize the physical tail before shifted windows can reach its padding. #}
 SET LR9 CR0 ;;
 {% if chunks > 1 %}INC LR9 {{ chunks-1 }} ;;{% endif %}
 clean_tail:
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR2 ;;
 MULT.RC.VE LR2 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.clean }} LR9 ;;
 INC LR9 {{ chunks }} ;;
 BLT.S LR9 LR5 clean_tail ;;
 {% endif %}
row:
 SET LR15 CR1 ; ADD LR11 LR12 {{ cr.batch_pitch }} ;;
channel:
 {% for c in range(chunks) %}{{ tile(c) }}{% endfor %}
 SET LR15 LR8 ; BLT.S LR8 {{ cr.weight_rows }} channel ;;
 INC LR12 {{ chunks }} ; INC LR13 1 ;;
 BLT.S {{ cr.last_y }} LR13 next_batch ;;
 BEQ LR0 CR0 row ;;
next_batch:
 ADD LR12 LR12 {{ cr.next_batch }} ; SET LR13 CR0 ;;
 INC LR14 1 ;;
 BLT.S LR14 {{ cr.out_rows }} more_batches ;;
 HALT ;;
more_batches:
 DEC LR14 1 ; BEQ LR0 CR0 row ;;
