{% set shifts = ['LR1', 'LR2', 'LR3'] %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.L' %}
{% set pitch = 2*stride-1 %}
{% set staged = stride == 2 or in0_d2 < 128 %}

{% macro load_weights() %}
 LD.MULT R0 LR10 {{ cr.weights }} ; INC LR10 1 ; SET LR11 CR0 ;;
 LD.MULT R1 LR10 {{ cr.weights }} ; INC LR10 1 ; SET LR12 LR2 ;;
{% endmacro %}

{% macro tap_column(dx, tag) %}
 SET LR8 LR7 ;;
 {% if dx %}{{ 'INC' if dx > 0 else 'DEC' }} LR8 {{ pitch }} ;;{% endif %}
 {% for dy in range(3) %}
 {% if stride == 2 or dy == 0 %}
 LD.MULT.CYCLIC LR8 {{ cr.sampled if staged else cr.in0 }} LR2 {% if stride == 2 and dy > 0 %}; INC LR8 1{% endif %} ;;
 {% endif %}
 {% set idx = 'LR2' if stride == 2 else shifts[dy] %}
 MULT.RC.VE {{ idx }} LR11 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR11 1 ;;
 MULT.RC.VE {{ idx }} LR12 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; INC LR12 1 ;;
 {% endfor %}
 {% if dx == -1 %}
 B {{ tag }}_done ;;
 {{ tag }}_skip:
 INC LR11 3 ; INC LR12 3 ;;
 {{ tag }}_done:
 {% endif %}
{%- endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 127 ; INC LR2 128 ; SET LR3 CR0 ;;
 INC LR3 129 ;;
 SET LR8 LR2 ;;
 INC LR8 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR8 ;;

 {% if staged %}
 {# Sanitize padding, and for stride two gather each vertical tap once per input column. #}
 SET LR4 CR0 ; SET LR5 CR0 ;;
 DEC LR4 1 ; DEC LR5 1 ;;
 sample:
 LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR2 ; INC LR4 1 ;;
 {% for idx in (shifts if stride == 2 else ['LR2']) %}
 {% set right = idx == 'LR3' %}
 MULT.RC.VE {{ idx }} {{ 'CR0' if right and in0_d2 == 1 else 'CR1' }} 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.STRIDE 64 on off LR0' if stride == 2 else 'ACC.ADD.FIRST' }} ; ACTIVATE.QUANTIZE identity {{ cr.gather_right if right else cr.tail }}.L {{ qi }} {{ cr.sampled }} LR5 ; INC LR5 1 ;;
 {% endfor %}
 BLT.S LR4 LR15 sample ;;
 {% endif %}

 SET LR4 CR0 ; SET LR9 CR0 ; SET LR13 CR0 ;;
 batch_group:
 SET LR15 CR0 ;;
 output_channel:
 SET LR5 LR4 ; SET LR6 CR0 ;;
 output_column:
 SET LR7 LR5 ; SET LR10 LR9 ; SET LR14 CR0 ;;
 INC LR14 {{ cin // groups }} ;;
 {{ load_weights() }}
 MULT.EE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 MULT.EE LR12 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; B filter ;;
 next_input_channel:
 {{ load_weights() }}
 filter:
 BEQ LR6 CR0 left_skip ;;
 {{ tap_column(-1, 'left') }}
 {{ tap_column(0, 'center') }}
 {% if (in0_d3 - 1) % stride == 0 %}
 SET LR8 LR6 ;;
 INC LR8 1 ;;
 BEQ LR8 {{ cr.out0_d3 }} finish_taps ;;
 {% endif %}
 {{ tap_column(1, 'right') }}
 finish_taps:
 ADD LR7 LR7 {{ cr.channel_pitch }} ; DEC LR14 1 ;;
 BLT.S CR0 LR14 next_input_channel ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ; INC LR6 1 ; INC LR5 {{ pitch*stride }} ;;
 BLT.S LR6 {{ cr.out0_d3 }} output_column ; INC LR13 1 ;;
 SET LR9 LR10 ; INC LR15 1 ;;
 BLT.S LR15 {{ cr.oc_per_group }} output_channel ;;
 ADD LR4 LR4 {{ cr.group_pitch }} ;;
 BEQ LR13 {{ cr.output_rows }} done ;;
 BNE LR9 {{ cr.last_weight }} batch_group ;;
 SET LR9 CR0 ;;
 B batch_group ;;
 done:
 HALT ;;
