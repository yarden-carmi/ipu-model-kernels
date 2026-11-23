{# The row kernel requires one input and one output per convolution group. #}
{% if cin == groups and cout == groups %}
{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set shifts = ['LR12', 'LR13', 'LR14'] %}

{% macro stage(y) %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ; SET LR3 CR0 ;;
 {% if y %}INC LR3 {{ 3*y }} ;;{% endif %}
 {% for x in range(3) %}
 ADD LR11 {{ shifts[x] }} LR15 ;;
 MULT.RC.VE {{ shifts[x] }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR14 ;;
 ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.wide_row }} LR3 ;;
 INC LR3 1 ;;
 {% endfor %}
{% endmacro %}

{# Prime one register, then fetch the next coefficient into the other
   register while accumulating the current product. LR3 is post-incremented. #}
{% macro products(operand) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 {% for part in range(3) %}
 MULT.RC.VV {{ operand }} R{{ part % 2 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; {% if part < 2 %}LD.MULT R{{ (part + 1) % 2 }} LR3 {{ cr.weights }} ; INC LR3 1 ;{% endif %} ;;
 {% endfor %}
{% endmacro %}

{% macro taps(y) %}
 {% if stride == 1 %}LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ;;{% endif %}
 SET LR3 LR2 ; SET LR11 CR0 ;;
 INC LR3 {{ 2 + 9*y }} ; {% if y %}INC LR11 {{ 3*y }} ;{% endif %} ;;
 {% for x in range(3) %}
 {% if stride == 2 %}
 LD.MULT.CYCLIC LR11 {{ cr.wide_row }} LR1 ;;
 INC LR11 1 ;;
 {% endif %}
 {{ products('LR1' if stride == 2 else shifts[x]) }}
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR7 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
 SET LR14 CR0 ; SET LR15 CR0 ; INC LR12 127 ;;
 INC LR13 128 ; INC LR14 129 ; INC LR15 64 ;;
 SET LR1 CR0 ;;
 INC LR1 255 ;;
 INC LR1 1 ;;
 DEC LR5 1 ;;
batch:
 SET LR6 CR0 ; SET LR2 CR0 ;;
channel:
 LD.MULT.CYCLIC LR2 {{ cr.weights }} LR0 ;;
 SET LR8 CR0 ; SET LR10 LR4 ;;
row:
 {% if stride == 2 %}
 BEQ LR8 CR0 stage_center ; SUB LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ stage(0) }}
stage_center:
 SET LR9 LR10 ;;
 {{ stage(1) }}
 BEQ LR8 {{ cr.last_y }} stage_done ; ADD LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ stage(2) }}
stage_done:
 {% endif %}
 SET LR3 LR2 ; SET LR9 LR10 ;;
 DEC LR3 1 ;;
 {% for part in range(3) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if part == 0 else 'ACC.ADD' }} ;;
 {% endfor %}
 BEQ LR8 CR0 center ;;
 SUB LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ taps(0) }}
 SET LR9 LR10 ;;
center:
 {{ taps(1) }}
 BEQ LR8 {{ cr.last_y }} finish ; ADD LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ taps(2) }}
finish:
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ qo }} {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR8 {{ stride }} ; ADD LR10 LR10 {{ cr.in0_d1 }} ;;
 {% if stride == 2 %}ADD LR10 LR10 {{ cr.in0_d1 }} ;;{% endif %}
 BLT.S LR8 {{ cr.end_y }} row ;;
 INC LR6 1 ; INC LR4 1 ; INC LR2 30 ;;
 BLT.S LR6 {{ cr.in0_d1 }} channel ;;
 INC LR7 1 ; ADD LR4 LR4 {{ cr.batch_gap }} ;;
 BLT.S LR7 {{ cr.in0_d0 }} batch ;;
{% endif %}
 HALT ;;
