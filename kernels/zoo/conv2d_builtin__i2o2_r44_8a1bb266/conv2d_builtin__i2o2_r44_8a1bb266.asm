{% set chunks = (h + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro weight() %}LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1{% endmacro %}

{# Fill the center and the adjacent slots of the cyclic input window. At
   an image edge, repeat the center row; fold masks the crossing tap. #}
{% macro column(tag, dx) %}
 {% if dx %}
 BEQ LR15 {{ 'CR0' if dx < 0 else cr.last_x }} skip_{{ tag }} ; INC LR5 6 ;;
 DEC LR5 6 ; {{ 'SUB' if dx < 0 else 'ADD' }} LR9 LR8 {{ cr.in_pitch }} ;;
 {% else %}
 SET LR9 LR8 ;;
 {% endif %}
 {% if chunks == 2 %}
 {% if cin == 1 %}
 ADD LR1 LR9 LR7 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR11 ;;
 {% else %}
 ADD LR1 LR10 LR10 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR11 ;;
 SUB LR1 LR9 LR1 ;;
 INC LR1 1 ;;
 {% endif %}
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR12 ;;
 {% else %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR11 ;;
 {% if chunks > 1 %}
 BEQ LR10 CR0 previous_{{ tag }} ; SET LR1 LR9 ;;
 DEC LR1 1 ;;
 previous_{{ tag }}:
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 BEQ LR10 {{ cr.last_chunk }} next_{{ tag }} ;;
 INC LR9 1 ;;
 next_{{ tag }}:
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR12 ;;
 {% else %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ;;
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR12 ;;
 {% endif %}
 {% endif %}
 {{ weight() }} ;;
 {% for idx in ['LR13', 'LR11', 'LR14'] %}
 {% for part in range(2) %}
 MULT.RC.VV {{ idx }} R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD{% if not loop.last or idx != 'LR14' %} ; {{ weight() }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 skip_{{ tag }}:
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
 SET LR11 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
 INC LR11 128 ; INC LR12 255 ; INC LR13 127 ;;
 INC LR12 1 ; SET LR14 LR11 ;;
 INC LR14 1 ;;
 batch:
 SET LR15 CR0 ;;
 x:
 SET LR5 CR0 ; SET LR10 CR0 ;;
 DEC LR5 1 ;;
 chunk:
 SET LR6 CR0 ; ADD LR3 LR4 LR10 ;;
 {% if chunks == 2 and cin == 1 %}
 SET LR7 CR1 ;;
 SUB LR7 LR7 LR10 ;;
 SUB LR7 LR7 LR10 ;;
 {% endif %}
 oc:
 {{ weight() }} ; {% if cin != 1 %}SET LR7 CR0 ; {% endif %}ADD LR8 LR2 LR10 ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; {{ weight() }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ;;
 ic:
 {{ column('left', -1) }}
 {{ column('center', 0) }}
 {{ column('right', 1) }}
 {% if cin != 1 %}
 INC LR8 {{ chunks }} ; INC LR7 1 ;;
 BLT.S LR7 {{ cr.cin }} ic ;;
 {% endif %}
 {% if chunks > 1 %}
 BEQ LR10 {{ cr.last_chunk }} tail ;;
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; B stored ;;
 tail:
 {% endif %}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 stored:
 INC LR6 1 ; INC LR3 {{ chunks }} ;;
 BLT.S LR6 {{ cr.cout }} oc ;;
 INC LR10 1 ;;
 BGE.S {{ cr.last_chunk }} LR10 chunk ;;
 ADD LR2 LR2 {{ cr.in_pitch }} ; ADD LR4 LR4 {{ cr.out_pitch }} ;;
 INC LR15 1 ;;
 BGE.S {{ cr.last_x }} LR15 x ;;
 BLT.S LR4 {{ cr.output_rows }} batch ;;
 HALT ;;
