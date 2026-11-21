{% set q = cr.qf_in0 ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1') %}
 MULT.VE LR0 {{ imm }} 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro encode(reg,pieces) %}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB') }}
 INC {{ reg }} 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro reset_chunks() %}
 SET LR5 LR2 ;;
 {{ at('LR9',32) }}
{% endmacro %}
{% macro next_chunk(label) %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 {{ label }} ;;
{% endmacro %}
{% macro average(label) %}
 {# Split the reduced sum and broadcast its reduction lane. #}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ at('LR10',0) }}{{ at('LR7',3) }}
 {{ scalar(first=true,imm='CR0') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}
 {{ load(b) }}{{ mul(first=(i==0)) }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}

 {{ at('LR0',0) }}{{ at('LR2',0) }}{{ at('LR3',128) }}
 ADD LR4 LR3 LR3 ;;
 ADD LR12 LR4 LR3 ;;
row_loop:
 ADD LR6 LR2 {{ cr.K }} ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }}
sum_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
 {{ next_chunk('sum_loop') }}
 {{ average('mean_scale') }}{{ save(27,3) }}

 {{ reset_chunks() }}
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ scalar(first=true) }}
 {% for n in range(27,30) %}{{ load(n) }}{{ scalar('SUB') }}{% endfor %}
 {{ encode('LR9',3) }}
 INC LR9 1 ;;
 {{ next_chunk('center_loop') }}

 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }}
variance_loop:
 SET LR1 LR9 ;;
 ADD LR7 LR9 CR1 ;;
 INC LR7 2 ;;
variance_parts:
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 SET LR10 LR9 ;;
variance_products:
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
 INC LR10 1 ;;
 BLT.S LR10 LR7 variance_products ;;
 INC LR1 1 ;;
 BLT.S LR1 LR7 variance_parts ;;
 SET LR9 LR7 ;;
 {{ next_chunk('variance_loop') }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Refine the quantized reciprocal square root using residual products. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(21,1) }}

 {{ reset_chunks() }}{{ at('LR11',0) }}{{ at('LR8',3) }}
output_loop:
 SET LR10 LR11 ;;
 {{ at('LR7',0) }}{{ scalar(first=true,imm='CR0') }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in range(19,22) %}{{ load(n) }}{{ mul() }}{% endfor %}
 ADD LR10 LR10 {{ cr.K }} ;;
 INC LR7 1 ;;
 BLT.S LR7 LR8 weight_loop ;;
 {{ save(9,3) }}
 {# Apply the centering terms directly, avoiding another rounding of the numerator. #}
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
 {% for n,slot in [(27,'LR3'),(28,'LR4'),(29,'LR12')] %}
 {{ at('LR1',n) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 {{ scalar(first=true,imm='CR0') }}
 {{ at('LR1',9) }}{{ at('LR7',12) }}
apply_weight:
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% for slot in ['LR3','LR4','LR12'] %}{{ mul(slot=slot,op='SUB') }}{% endfor %}
 INC LR1 1 ;;
 BLT.S LR1 LR7 apply_weight ;;
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar() }}
 ADD LR10 LR10 {{ cr.K }} ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 INC LR11 1 ;;
 {{ next_chunk('output_loop') }}
 SET LR2 LR6 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
