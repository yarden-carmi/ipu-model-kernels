{% set q = cr.qf_in0 ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 SET LR1 CR0 {% if n %};;{% else %};{% endif %}
 {% if n %}INC LR1 {{ n }} ;{% endif %}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds='CR15.L') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',next=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}{% if next %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds='CR15.L') %}
 {% for i in range(pieces) %}
 {% if not loop.first %}INC {{ reg }} 1 ;{% endif %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds) }}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro start_pass() %}
 ADD LR6 LR14 {{ cr.K }} ; SET LR5 LR14 ; SET LR9 CR0 ;;
 DEC LR6 1 ; INC LR9 32 ;;
{% endmacro %}
{% macro next_chunk(label) %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 {{ label }} ;;
{% endmacro %}
{% macro sum_pass(label,ds,i6='') %}
{{ label }}:
 LD.MULT R0 LR5 {{ cr.in0 }} {{ i6 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {{ next_chunk(label) }}
{% endmacro %}
{% macro center_pass(label,ds,i6='') %}
{{ label }}:
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 CR0 {{ i6 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {{ encode('LR9',3,ds) }}
 INC LR9 1 ;;
 {{ next_chunk(label) }}
{% endmacro %}
{% macro variance_pass(label,ds,i6='') %}
{{ label }}:
 SET LR1 LR9 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 {{ i6 }} ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {% for slot in ['LR0','LR3','LR4'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }}{% if loop.last and i < 2 %} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ;;
 {{ next_chunk(label) }}
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
 {{ load(3) }}
 {% for j in range(3) %}{{ mul(next=not loop.last) }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}
 {{ load(b) }}{{ mul(first=(i==0),next=true) }}
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR14 CR0 ;;
 {{ at('LR3',128) }}
 ADD LR4 LR3 LR3 ;;
 ADD LR12 LR4 LR3 ;;
row_loop:
 {{ start_pass() }}{{ scalar(first=true,imm='CR0') }}
 {{ sum_pass('sum_a','CR15.L') }}
 {{ sum_pass('sum_b','CR14.L','; INC LR6 1') }}
 {{ average('mean_scale') }}{{ save(27,3) }}

 {{ start_pass() }}
 {{ center_pass('center_a','CR15.L') }}
 INC LR6 1 ;;
 {{ center_pass('center_b','CR14.L') }}

 {{ start_pass() }}{{ scalar(first=true,imm='CR0') }}
 {{ variance_pass('variance_a','CR15.L') }}
 INC LR6 1 ;;
 {{ variance_pass('variance_b','CR14.L') }}
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
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true,next=true) }}
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

 SET LR5 LR14 ; SET LR15 LR2 ; SET LR11 CR0 ;;
output_loop:
 {{ load(19,true) }}
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in ['LR0','LR3','LR4'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}{% if i < 2 and loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
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
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ;;
 INC LR11 1 ; INC LR15 1 ;;
 {{ next_chunk('output_loop') }}
 SET LR2 LR15 ; ADD LR14 LR14 LR13 ;;
 BLT.S LR14 {{ cr.M }} no_wrap ;;
 SUB LR14 LR14 {{ cr.M }} ;;
 ADD LR14 LR14 {{ cr.K }} ;;
no_wrap:
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
