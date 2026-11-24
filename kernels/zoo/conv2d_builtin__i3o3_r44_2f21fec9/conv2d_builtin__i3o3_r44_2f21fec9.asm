{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set last_base = cr.clean if in0_d3 % 128 else cr.in0 %}

{% macro coeffs() %}
 LD.MULT R0 LR5 {{ cr.weights }} ; SET LR9 CR0 ; SET LR10 CR0 ;;
 INC LR5 1 ; INC LR10 128 ;;
 LD.MULT R1 LR5 {{ cr.weights }} ;;
 INC LR5 1 ;;
{% endmacro %}

{% macro panel(chunk, p, last) %}
 {{ coeffs() }}
channels_{{ chunk }}_{{ p }}:
 LD.MULT.CYCLIC LR8 {{ last_base if chunks == 1 else cr.in0 }} {{ 'LR12' if chunk == 0 else 'LR14' }} ;;
 {% if chunks == 2 %}
 INC LR8 1 ;;
 LD.MULT.CYCLIC LR8 {{ last_base }} {{ 'LR14' if chunk == 0 else 'LR12' }} ;;
 {% endif %}
 {% for x in range(3) %}
 MULT.RC.VE LR{{ 11+x }} LR9 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 MULT.RC.VE LR{{ 11+x }} LR10 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 {% if x < 2 or in0_d1 != 1 %}
 INC LR9 1 ; INC LR10 1 {% if x == 2 %}; INC LR8 1 ; BLT.S LR9 {{ cr.panel_end }}.{{ 'H' if last else 'L' }} channels_{{ chunk }}_{{ p }}{% endif %} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}

{% macro tile(chunk) %}
 SET LR12 CR0 ; SET LR14 CR0 ;;
 INC LR12 128 ; INC LR14 128 ;;
 INC {{ 'LR14' if chunk == 0 else 'LR12' }} 128 ;;
 SET LR11 LR12 ; SET LR13 LR12 ;;
 DEC LR11 1 ; INC LR13 1 ;;
 MULT.EE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; SET LR6 LR3 ; SUB LR7 LR2 {{ cr.pitch }} ;;
 DEC LR6 1 ;;
ky_{{ chunk }}:
 BLT.S LR6 CR0 skip_{{ chunk }} ; SET LR8 LR7 ;;
 BGE.S LR6 {{ cr.in0_d2 }} skip_{{ chunk }} ;;
 {% for p in range((in0_d1 + 31) // 32) %}
 {{ panel(chunk, p, loop.last) }}
 {% endfor %}
 B next_{{ chunk }} ;;
skip_{{ chunk }}:
 ADD LR5 LR5 {{ cr.panel_rows }} ;;
next_{{ chunk }}:
 INC LR6 1 ; ADD LR7 LR7 {{ cr.pitch }} ; SET LR8 LR3 ;;
 INC LR8 2 ;;
 BLT.S LR6 LR8 ky_{{ chunk }} ;;
 {{ coeffs() }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 MULT.EE LR10 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail ~ '.L' if chunk == chunks-1 else full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
 INC LR1 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 {% if in0_d3 % 128 %}
 SET LR3 CR0 ; SET LR4 CR0 ;;
 {% if chunks == 2 %}INC LR4 1 ;;{% endif %}
 clean_batch:
 SET LR5 CR0 ;;
 clean_y:
 SET LR6 CR0 ;;
 clean_channel:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.clean }} LR4 ;;
 INC LR4 {{ chunks }} ; INC LR6 1 ;;
 SET LR7 CR0 ;;
 INC LR7 {{ in0_d1 }} ;;
 BLT.S LR6 LR7 clean_channel ;;
 INC LR5 1 ;;
 BLT.S LR5 {{ cr.in0_d2 }} clean_y ;;
 INC LR3 1 ;;
 BLT.S LR3 LR15 clean_batch ;;
 {% endif %}
 LD.MULT R0 LR0 {{ cr.weights }} ;;
 {# Zero guard rows around the active cyclic window. #}
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR0 ; SET LR14 CR0 ;;
 INC LR14 192 ;;
 INC LR14 192 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR14 ;;
 {% if chunks == 1 %}
 DEC LR14 128 ;;
 LD.MULT.CYCLIC LR0 {{ cr.weights }} LR14 ;;
 {% endif %}
batch:
 SET LR3 CR0 ;;
row:
 SET LR4 CR0 ; SET LR5 CR1 ;;
channel:
 {% for chunk in range(chunks) %}
 {% if chunk %}SUB LR5 LR5 {{ cr.filter_rows }} ;;{% endif %}
 {{ tile(chunk) }}
 {% endfor %}
 INC LR4 1 ;;
 BLT.S LR4 {{ cr.out0_d1 }} channel ;;
 INC LR3 1 ; ADD LR2 LR2 {{ cr.pitch }} ;;
 BLT.S LR3 {{ cr.in0_d2 }} row ;;
 DEC LR15 1 ;;
 BNE LR15 CR0 batch ;;
 HALT ;;
