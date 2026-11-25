{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}

{# The same scalar input multiplies a vector of output-channel weights.
   Alternate cyclic slots to overlap each MAC with the next weight load. #}
{% macro macs(selectors) %}
 LD.MULT.CYCLIC LR6 {{ cr.weights }} LR0 ; INC LR6 1 ;;
 {% for sel in selectors %}
 {% set rc = 'LR0' if loop.index0 % 2 == 0 else 'LR13' %}
 {% set next = 'LR13' if loop.index0 % 2 == 0 else 'LR0' %}
 MULT.RC.VE {{ rc }} {{ sel }} 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if loop.first and sel == 'CR1' else 'ACC.ADD' }}{% if not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.weights }} {{ next }} ; INC LR6 1{% endif %} ;;
 {% endfor %}
{% endmacro %}

{% macro tapline(ky) %}
 SET LR7 LR1 ; ADD LR8 LR4 LR1 ;;
 {% if ky %}INC LR7 {{ ky }} ; INC LR8 {{ ky }} ;;{% endif %}
 BLT.S LR7 CR0 skip_{{ ky }} ;;
 BGE.S LR7 {{ cr.in0_d2 }} skip_{{ ky }} ;;
 SET LR9 {{ cr.in0_d1 }} ;;
 ic_{{ ky }}:
 LD.MULT R0 LR8 {{ cr.in0 }} ; DEC LR9 1 ;;
 {{ macs(['LR10', 'LR10', 'LR10', 'LR11', 'LR11', 'LR11', 'LR12', 'LR12', 'LR12']) }}
 ADD LR8 LR8 {{ cr.in0_d2 }} ; BNE LR9 CR0 ic_{{ ky }} ;;
 B end_{{ ky }} ;;
 skip_{{ ky }}:
 ADD LR6 LR6 {{ cr.tap_rows }} ;;
 end_{{ ky }}:
{% endmacro %}

 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR13 CR0 ;;
 INC LR13 128 ;;
 LD.MULT R1 LR14 {{ cr.weights }} ;;
 SET LR14 CR0 ;;
 INC LR14 255 ;;
 batch:
 SET LR1 CR0 ;;
 {% if padding %}DEC LR1 {{ padding }} ;;{% endif %}
 y:
 SET LR2 CR0 ;;
 x:
 SET LR6 CR0 ; SET LR10 LR2 ; SET LR11 LR2 ;;
 SET LR12 LR2 ;;
 DEC LR6 1 ;;
 {% if padding %}
 INC LR12 1 ; BNE LR2 CR0 left_interior ;;
 SET LR10 LR14 ;;
 B left_done ;;
 left_interior:
 DEC LR10 1 ;;
 left_done:
 BNE LR12 {{ cr.in0_d3 }} right_done ;;
 SET LR12 LR14 ;;
 right_done:
 {% else %}
 INC LR11 1 ; INC LR12 2 ;;
 {% endif %}
 {{ macs(['CR1', 'CR1', 'CR1']) }}
 {% for ky in range(3) %}{{ tapline(ky) }}{% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR2 {{ stride }} ;;
 INC LR5 1 ; BLT.S LR2 {{ cr.x_end }} x ;;
 INC LR1 {{ stride }} ;;
 BLT.S LR1 {{ cr.y_end }} y ;;
 ADD LR4 LR4 {{ cr.plane_rows }} ; DEC LR3 1 ;;
 BNE LR3 CR0 batch ;;
 HALT ;;
