{# Depthwise 3x3, one input and output per group. #}
{% if cin == groups and cout == groups %}
{% set full = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set shifts = ['LR12', 'LR13', 'LR14'] %}

{# Stage stride-two taps in output coordinates. Both halves are needed
   because ACC.STRIDE selects even lanes from a 64-column panel. #}
{% macro stage(y) %}
 LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ; SET LR3 CR0 ;;
 {% if y %}INC LR3 {{ 3*y }} ;;{% endif %}
 {% for x in range(3) %}
 ADD LR11 {{ shifts[x] }} LR15 ;;
 MULT.RC.VE {{ shifts[x] }} CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR0 ;;
 MULT.RC.VE LR11 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.STRIDE 64 on off LR14 ;;
 ACTIVATE.QUANTIZE identity {{ tail }} {{ qi }} {{ cr.taps }} LR3 ;;
 INC LR3 1 ;;
 {% endfor %}
{% endmacro %}

{% macro window(op) %}
 BEQ LR8 CR0 {{ op }}_center ; SUB LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ stage(0) if op == 'stage' else accumulate(0) }}
{{ op }}_center:
 SET LR9 LR10 ;;
 {{ stage(1) if op == 'stage' else accumulate(1) }}
 BEQ LR8 {{ cr.last_y }} {{ op }}_done ; ADD LR9 LR10 {{ cr.in0_d1 }} ;;
 {{ stage(2) if op == 'stage' else accumulate(2) }}
{{ op }}_done:
{% endmacro %}

{% macro weight(r) %}LD.MULT R{{ r }} LR3 {{ cr.weights }} ; INC LR3 1{% endmacro %}

{% macro accumulate(y) %}
 {% if stride == 1 %}LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR13 ;;{% endif %}
 SET LR3 LR2 ; SET LR11 CR0 ;;
 INC LR3 {{ 2 + 9*y }} ; {% if y %}INC LR11 {{ 3*y }} ; {% endif %};;
 {% for x in range(3) %}
 {% if stride == 2 %}LD.MULT.CYCLIC LR11 {{ cr.taps }} LR1 ;; INC LR11 1 ;;{% endif %}
 {{ weight(0) }} ;;
 {% for part in range(3) %}
 MULT.RC.VV {{ 'LR1' if stride == 2 else shifts[x] }} R{{ part % 2 }} 0 LR0 {{ full }} {{ qi }} ; ACC.ADD {% if part < 2 %}; {{ weight((part+1)%2) }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 DEC LR5 1 ;;
 SET LR7 {{ cr.in0_d0 }} ; SET LR12 CR0 ; SET LR13 CR0 ;;
 SET LR14 CR0 ; SET LR15 CR0 ; INC LR12 127 ;;
 INC LR13 128 ; INC LR14 129 ; INC LR15 64 ;;
 SET LR1 CR0 ;; INC LR1 255 ;; INC LR1 1 ;;
batch:
 SET LR8 CR0 ;;
row:
 SET LR10 LR4 ; SET LR2 CR0 ; SET LR6 {{ cr.in0_d1 }} ;;
channel:
 {% if stride == 2 %}{{ window('stage') }}{% endif %}
 SET LR3 LR2 ;;
 DEC LR3 1 ;;
 {% for part in range(3) %}
 {{ weight(0) }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; {{ 'ACC.ADD.FIRST' if part == 0 else 'ACC.ADD' }} ;;
 {% endfor %}
 {{ window('accumulate') }}
 ACTIVATE.QUANTIZE {{ act_out0 }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR10 1 ;;
 INC LR2 30 ; DEC LR6 1 ;;
 BNE LR6 CR0 channel ;;
 INC LR8 {{ stride }} ; ADD LR4 LR4 {{ cr.pitch }} ;;
 BLT.S LR8 {{ cr.in0_d2 }} row ;;
 SUB LR4 LR4 {{ cr.batch_fix }} ; DEC LR7 1 ;;
 BNE LR7 CR0 batch ;;
{% endif %}
 HALT ;;
