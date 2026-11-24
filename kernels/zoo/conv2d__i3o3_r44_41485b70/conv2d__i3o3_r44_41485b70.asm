{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set data = cr.parity %}

{# LR0 is zero; LR1 and LR2 are the two input slots. Their neighboring
   lanes supply horizontal zero padding even for a full-width input. #}
{% macro vertical(ky) %}
 ADD LR14 LR9 {{ cr.ky_rows }} ; SET LR10 LR6 ;;
 {% if ky == 0 %}
 BEQ LR6 LR0 end_{{ ky }} ; DEC LR10 1 ;;
 {% elif ky == 2 %}
 BEQ LR6 {{ cr.last_y }} end_{{ ky }} ; INC LR10 1 ;;
 {% endif %}
 {% if stride == 2 %}ADD LR10 LR10 LR10 ;;{% endif %}
 panel_{{ ky }}:
 LD.MULT R0 LR9 {{ cr.weights }} ; SET LR11 LR0 ; SET LR12 LR1 ;;
 INC LR9 1 ; LD.MULT R1 LR9 {{ cr.weights }} ; SET LR13 LR0 ;;
 INC LR9 1 ;;
 {% if cin % 42 %}
 INC LR13 {{ 3 * (cin % 42) }} ; BEQ LR9 LR14 input_{{ ky }} ;;
 SET LR13 LR0 ;;
 {% endif %}
 INC LR13 126 ;;
 input_{{ ky }}:
 LD.MULT.CYCLIC LR10 {{ data }} LR1 {% if stride == 2 %}; SET LR15 LR10{% endif %} ;;
 {% if stride == 2 %}
 INC LR15 1 ;;
 LD.MULT.CYCLIC LR15 {{ data }} LR2 ;;
 {% endif %}
 {% for addr in ['LR3', 'LR1', 'LR4'] %}
 MULT.RC.VE {{ addr }} LR11 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 MULT.RC.VE {{ addr }} LR12 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR11 1 ;;
 INC LR12 1 {% if loop.last %}; ADD LR10 LR10 {{ cr.pitch }}{% endif %} ;;
 {% endfor %}
 BLT.S LR11 LR13 input_{{ ky }} ;;
 BLT.S LR9 LR14 panel_{{ ky }} ;;
 end_{{ ky }}:
 SET LR9 LR14 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR5 CR0 ;;
 INC LR1 128 ; INC LR2 255 ; SET LR7 CR1 ;;
 INC LR2 1 ; SET LR3 LR1 ; SET LR4 LR1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ; DEC LR3 1 ; INC LR4 1 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR2 ;;
 {# Clear non-view lanes. For stride two, also split horizontal parity. #}
 SET LR8 LR0 ; SET LR9 LR0 ;;
 parity_row:
 LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR1 ;;
 MULT.RC.VE LR1 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ cr.input_ds }}.L {{ qi }} {{ cr.parity }} LR9 ;;
 {% if stride == 2 %}
 LD.MULT.CYCLIC LR9 {{ cr.parity }} LR1 ;;
 {% for addr in ['LR1', 'LR4'] %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE {{ addr }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 ACTIVATE.QUANTIZE identity {{ cr.store_ds if loop.first else cr.input_ds }}.{{ 'L' if loop.first else 'H' }} {{ qi }} {{ cr.parity }} LR9 ;;
 INC LR9 1 ;;
 {% endfor %}
 {% else %}
 INC LR9 1 ;;
 {% endif %}
 INC LR8 1 ;;
 BLT.S LR8 {{ cr.input_rows }} parity_row ;;
 {% if stride == 2 %}
 SET LR3 LR2 ; SET LR4 LR2 ;;
 DEC LR3 1 ;;
 {% endif %}

 channel:
 SET LR6 LR0 ;;
 row:
 LD.MULT R0 LR7 {{ cr.weights }} ; SET LR9 LR7 ; SET LR11 LR0 ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR11 1 ; INC LR9 1 ;;
 MULT.EE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 {% for ky in range(3) %}{{ vertical(ky) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.L {{ qo }} {{ cr.out0 }} LR5 ;;
 INC LR5 1 ; INC LR6 {{ stride }} ;;
 BGE.S {{ cr.last_y }} LR6 row ;;
 SET LR7 LR9 ; BLT.S LR9 {{ cr.weight_end }} channel ;;
 HALT ;;
