{% set chunks = (in0_d3 + 127) // 128 %}
{% set full = cr.full ~ '.L' %}
{% set q = cr.qf_in0 ~ '.L' %}

{# Each horizontal tap is a cyclic read across the current width row and
   its neighbor. At the image boundary a shifted mask suppresses the wrap. #}
{% macro panel(c, ky) %}
{% set tag = c ~ '_' ~ ky %}
 SET LR7 LR5 ; SET LR9 {{ cr.cin }} ;;
 {% if c %}INC LR7 {{ c }} ;;{% endif %}
 channel_{{ tag }}:
 LD.MULT.CYCLIC LR7 {{ cr.clean }} LR10 ;;
 {% if chunks == 2 %}
 SET LR14 LR7 ; SET LR13 CR0 ;;
 {% if c == 0 %}INC LR14 1 ; INC LR13 255 ;; INC LR13 1 ;;
 {% else %}DEC LR14 1 ;;{% endif %}
 LD.MULT.CYCLIC LR14 {{ cr.clean }} LR13 ;;
 {% endif %}
 SET LR14 CR0 ;;
 DEC LR14 1 ;;
 {% for part in range(2) %}
 LD.MULT R0 LR8 {{ cr.weights }} ; SET LR13 LR14 ;;
 {% for x in range(3) %}
 {% set mask = 'CR1' if x == 0 and c == 0 else ('LR14' if x == 2 and c == chunks - 1 and in0_d3 % 128 == 0 else 'LR0') %}
 {# mask_shift is an LR, so use LR14 for the negative shift and LR6 for +1. #}
 MULT.RC.VE {{ ['LR11','LR10','LR12'][x] }} LR13 0 {{ 'LR6' if mask == 'CR1' else mask }} {{ full }} {{ q }} ; ACC.ADD ; INC LR13 1 ;;
 {% endfor %}
 INC LR8 1 ;;
 {% endfor %}
 INC LR7 {{ chunks }} ; DEC LR9 1 ;;
 BNE LR9 CR0 channel_{{ tag }} ;;
{% endmacro %}

{% macro tile(c) %}
 SET LR8 LR4 ;;
 {% for part in range(2) %}
 LD.MULT R0 LR8 {{ cr.weights }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; {{ 'ACC.ADD.FIRST' if part == 0 else 'ACC.ADD' }} ; INC LR8 1 ;;
 {% endfor %}
 SUB LR5 LR2 {{ cr.pitch }} ;;
 BEQ LR3 CR0 top_pad_{{ c }} ;;
 {{ panel(c, 0) }}
 BEQ LR0 CR0 center_{{ c }} ;;
 top_pad_{{ c }}:
 ADD LR8 LR8 {{ cr.panel }} ;;
 center_{{ c }}:
 SET LR5 LR2 ;;
 {{ panel(c, 1) }}
 ADD LR5 LR2 {{ cr.pitch }} ; ADD LR14 LR3 CR1 ;;
 BGE.S LR14 {{ cr.in0_d2 }} bottom_pad_{{ c }} ;;
 {{ panel(c, 2) }}
 BEQ LR0 CR0 store_{{ c }} ;;
 bottom_pad_{{ c }}:
 ADD LR8 LR8 {{ cr.panel }} ;;
 store_{{ c }}:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ full if c < chunks - 1 else cr.tail ~ '.L' }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR15 {{ cr.in0_d0 }} ; SET LR6 CR1 ; SET LR10 CR0 ;;
 INC LR10 128 ; SET LR11 CR0 ; SET LR12 CR0 ;;
 INC LR11 127 ; INC LR12 129 ;;
 {# Clear inactive lanes before any shifted window can read them. #}
clean_rows:
 {% for c in range(chunks) %}
 LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full if c < chunks - 1 else cr.tail ~ '.L' }} {{ q }} {{ cr.clean }} LR2 ;;
 INC LR2 1 ;;
 {% endfor %}
 BLT.S LR2 LR14 clean_rows ;;
 SET LR2 CR0 ;;
batch:
 SET LR3 CR0 ;;
row:
 SET LR4 CR0 ;;
output_channel:
 {% for c in range(chunks) %}{{ tile(c) }}{% endfor %}
 SET LR4 LR8 ;;
 BLT.S LR4 {{ cr.weight_end }} output_channel ;;
 ADD LR2 LR2 {{ cr.pitch }} ; INC LR3 1 ;;
 BLT.S LR3 {{ cr.in0_d2 }} row ;;
 DEC LR15 1 ;;
 BNE LR15 CR0 batch ;;
 HALT ;;
