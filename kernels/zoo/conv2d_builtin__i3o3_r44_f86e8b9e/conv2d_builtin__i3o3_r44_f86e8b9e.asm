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
 {# One stride operation gathers the even lanes of the full shifted row. #}
 MULT.RC.VE {{ shifts[x] }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qi }} {{ cr.wide_row }} LR3 ; {% if x %}INC LR3 1 ;{% endif %} ;;
 {% endfor %}
{% endmacro %}

{# Stride-one path streams the coefficient rows. The last multiply of
   each group can prime the first coefficient of the next group. #}
{% macro direct_products(next_group, branch='', bank=0) %}
 {% for part in range(9) %}
 MULT.RC.VV {{ shifts[part // 3] }} R{{ (part + bank) % 2 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; {% if part < 8 or next_group %}LD.MULT R{{ (part + bank + 1) % 2 }} LR3 {{ cr.weights }} ; INC LR3 1 ;{% endif %} {% if part == 8 %}{{ branch }}{% endif %} ;;
 {% endfor %}
{% endmacro %}

{# Prime one register, then fetch the next coefficient into the other
   register while accumulating the current product. LR3 is post-incremented. #}
{% macro products(operands) %}
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 {% for part in range(9) %}
 MULT.RC.VV {{ operands[part // 3] }} R{{ part % 2 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD ; {% if part < 8 %}LD.MULT R{{ (part + 1) % 2 }} LR3 {{ cr.weights }} ; INC LR3 1 ;{% endif %} ;;
 {% endfor %}
{% endmacro %}

{% macro taps(y) %}
 SET LR3 LR2 ; SET LR11 CR0 ;;
 INC LR3 {{ 2 + 9*y }} ; {% if y %}INC LR11 {{ 3*y }} ;{% endif %} ;;
 LD.MULT.CYCLIC LR11 {{ cr.wide_row }} LR0 ;;
 LD.MULT.CYCLIC LR11 {{ cr.wide_row }} LR13 ; INC LR11 1 ;;
 LD.MULT.CYCLIC LR11 {{ cr.wide_row }} LR1 ; INC LR11 1 ;;
 {{ products(['LR0', 'LR13', 'LR1']) }}
{% endmacro %}

 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 SET LR7 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
 SET LR14 CR0 ; SET LR15 CR0 ; INC LR12 127 ;;
 INC LR13 128 ; INC LR14 129 ; INC LR15 12 ;;
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
 {% if stride == 1 %}
 LD.MULT R0 LR2 {{ cr.weights }} ; SET LR3 LR2 ;;
 {% for part in range(3) %}
 MULT.EE {{ 'LR0' if part % 2 == 0 else 'LR13' }} CR1 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if part == 0 else 'ACC.ADD' }} ; LD.MULT R{{ (part + 1) % 2 if part < 2 else 0 }} LR3 {{ cr.weights }} ; INC LR3 1 ; {% if part == 2 %}BEQ LR8 CR0 direct_first ;{% endif %} ;;
 {% endfor %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ; SUB LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ direct_products(true, 'B direct_center ;') }}
 direct_first:
 LD.MULT R1 LR3 {{ cr.weights }} ; ADD LR3 LR2 LR15 ;;
 direct_center:
 LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR13 ;;
 {# Each nine-product group starts in the other coefficient register. #}
 {{ direct_products(true, 'BEQ LR8 ' ~ cr.last_y ~ ' finish ;', 1) }}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ; ADD LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ direct_products(false) }}
 {% else %}
 BEQ LR8 CR0 stage_center ; SUB LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ stage(0) }}
stage_center:
 SET LR9 LR10 ;;
 {{ stage(1) }}
 BEQ LR8 {{ cr.last_y }} stage_done ; ADD LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ stage(2) }}
stage_done:
 SET LR3 LR2 ; SET LR9 LR10 ;;
 DEC LR3 1 ;;
 LD.MULT R0 LR3 {{ cr.weights }} ; INC LR3 1 ;;
 {% for part in range(3) %}
 MULT.EE {{ 'LR0' if part % 2 == 0 else 'LR13' }} CR1 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if part == 0 else 'ACC.ADD' }} ; {% if part < 2 %}LD.MULT R{{ (part + 1) % 2 }} LR3 {{ cr.weights }} ; INC LR3 1 ;{% endif %} ;;
 {% endfor %}
 BEQ LR8 CR0 center ;;
 SUB LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ taps(0) }}
 SET LR9 LR10 ;;
center:
 {{ taps(1) }}
 BEQ LR8 {{ cr.last_y }} finish ; ADD LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ taps(2) }}
 {% endif %}
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
