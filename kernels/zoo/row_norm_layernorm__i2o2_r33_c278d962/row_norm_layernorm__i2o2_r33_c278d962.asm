{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
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
{% macro average(label) %}
 {# Broadcast lane zero of the running reduction, then scale by 1/channels. #}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
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
 {{ load(a+i,true) }}{{ load(b) }}{{ mul(first=loop.first) }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}
{% macro reset_chunks() %}
 SET LR5 LR2 ;;
 {{ at('LR9',32) }}
{% endmacro %}
{% macro next_chunk(label) %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 {{ label }} ;;
{% endmacro %}
{% macro sum_chunk(ds) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM LR0 {{ ds }} ;;
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ;;
row_loop:
 ADD LR6 LR2 {{ cr.K }} ;;
 DEC LR6 1 ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }}
 BEQ LR5 LR6 sum_tail ;;
sum_loop:
 {{ sum_chunk(full) }}
 {{ next_chunk('sum_loop') }}
sum_tail:
 {{ sum_chunk(tail) }}
 {{ average('mean_scale') }}{{ save(27,3) }}

 {{ reset_chunks() }}
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ scalar(first=true,fmt=iq) }}
 {% for n in range(27,30) %}{{ load(n) }}{{ scalar('SUB') }}{% endfor %}
 BNE LR5 LR6 center_full ;;
 {{ encode('LR9',3,tail) }}
 BEQ LR0 CR0 variance_start ;;
center_full:
 {{ encode('LR9',3) }}
 INC LR9 1 ; INC LR5 1 ; BEQ LR0 CR0 center_loop ;;

variance_start:
 INC LR6 1 ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }}
variance_loop:
 SET LR1 LR9 ; ADD LR7 LR9 CR1 ;;
 INC LR7 2 ;;
variance_parts:
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; SET LR10 LR9 ;;
variance_products:
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR10 1 ;;
 BLT.S LR10 LR7 variance_products ;;
 INC LR1 1 ;;
 BLT.S LR1 LR7 variance_parts ;;
 SET LR9 LR7 ;;
 {{ next_chunk('variance_loop') }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Two Newton corrections for the table and quantization error in rsqrt. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(21,1) }}

 {{ reset_chunks() }}
 SET LR11 CR0 ;;
 {{ at('LR8',3) }}
 DEC LR6 1 ;;
output_loop:
 SET LR10 LR11 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0') }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in range(19,22) %}{{ load(n) }}{{ mul() }}{% endfor %}
 ADD LR10 LR10 {{ cr.K }} ; INC LR7 1 ;;
 BLT.S LR7 LR8 weight_loop ;;
 {{ save(9,3) }}
 {{ scalar(first=true,imm='CR0') }}
 ADD LR12 LR9 LR8 ;;
apply_centered_part:
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 {% for n in range(9,12) %}{{ load(n) }}{{ mul() }}{% endfor %}
 INC LR9 1 ;;
 BLT.S LR9 LR12 apply_centered_part ;;
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar() }}
 ADD LR10 LR10 {{ cr.K }} ;;
 {% endfor %}
 BNE LR5 LR6 output_full ;;
 {{ store(tail) }}
 ADD LR2 LR6 CR1 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
output_full:
 {{ store(full) }}
 INC LR5 1 ; INC LR11 1 ; BEQ LR0 CR0 output_loop ;;
