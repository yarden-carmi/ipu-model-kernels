{% set q = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(n) %}
 SET LR1 CR0 ;;
 {% if n %}INC LR1 {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at(n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,ds=full) %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',ds=full) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear() %}
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at(n) }}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {% if not loop.last %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ vec('SUB') }}
 INC LR1 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{# Broadcast the reduced scalar and multiply its split by split 1/channels. #}
{% macro mean(label) %}
 {{ save(0,3) }}
 {{ at(0) }}
 {% for i in range(3) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% if not loop.last %}INC LR1 1 ;;{% endif %}
 {% endfor %}
 {{ save(3,3) }}
 {{ clear() }}
 SET LR10 CR0 ;;
 {{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for i in range(3,6) %}{{ load(i) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro square_sum(ds) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 INC LR9 1 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 INC LR9 1 ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}
 {% for j in range(2) %}{{ load(b+j) }}{{ mul(first=i==0 and j==0) }}{% endfor %}
 {% endfor %}
 {{ save(dest) }}
{% endmacro %}

 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
 SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR4 CR0 ;;
 SET LR7 CR0 ;;
 INC LR7 3 ;;
 SET LR13 CR0 ;;
row_loop:
 SET LR5 LR4 ;;
 ADD LR6 LR4 {{ cr.K }} ;;
 {{ clear() }}
sum_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
 {{ mean('mean_scale') }}{{ save(6,3) }}

 SET LR5 LR4 ;;
 SET LR9 CR0 ;;
 INC LR9 32 ;;
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ vec(first=true) }}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR9 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ vec('SUB') }}
 INC LR9 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR9 ;;
 INC LR9 1 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 center_loop ;;

 {{ clear() }}
 SET LR5 CR0 ;;
 INC LR5 1 ;;
 SET LR9 CR0 ;;
 INC LR9 32 ;;
 BLT.S LR5 {{ cr.K }} variance_full ;;
 BLT.S CR0 CR1 variance_tail ;;
variance_full:
 {{ square_sum(full) }}
 INC LR5 1 ;;
 BLT.S LR5 {{ cr.K }} variance_full ;;
variance_tail:
 {{ square_sum(tail) }}
 {{ mean('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec() }}

 {# Seed reciprocal square root, then refine twice against the saved variance. #}
 {{ at(8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ vec('SUB') }}{{ save(22,1) }}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {% for src,count,dst in [(8,1,19),(19,2,23)] %}
 {{ clear() }}
 {% for n in [11,12,22] %}
 {{ load(n,true) }}{{ load(13) }}{{ mul() }}{{ load(14) }}{{ mul() }}
 {% endfor %}
 {{ save(15) }}
 {{ clear() }}
 {% for i in range(count) %}
 {{ load(src+i,true) }}{{ load(15) }}{{ mul() }}{{ load(16) }}{{ mul() }}
 {% endfor %}
 {{ save(17) }}
 {% for i in range(count) %}
 {{ load(src+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}
 {{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 {{ save(dst) }}
 {% if not loop.last %}{{ product(dst,dst,13) }}{% endif %}
 {% endfor %}

 SET LR11 CR0 ;;
 SET LR9 CR0 ;;
 INC LR9 32 ;;
output_loop:
 SET LR10 LR11 ;;
 SET LR5 CR0 ;;
 {{ clear() }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in [23,24] %}{{ load(n) }}{{ mul() }}{% endfor %}
 ADD LR10 LR10 {{ cr.K }} ;;
 INC LR5 1 ;;
 BLT.S LR5 LR7 weight_loop ;;
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {% for n in [9,10,11] %}{{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ vec() }}
 ADD LR10 LR10 {{ cr.K }} ;;
 {% endfor %}
 INC LR11 1 ;;
 BLT.S LR11 {{ cr.K }} output_full ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
 ADD LR4 LR4 LR12 ;;
 INC LR13 1 ;;
 BLT.S LR13 {{ cr.rows }} row_loop ;;
 HALT ;;
output_full:
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
 BLT.S CR0 CR1 output_loop ;;
