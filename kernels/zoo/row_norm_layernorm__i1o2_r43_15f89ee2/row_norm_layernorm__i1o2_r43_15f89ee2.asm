{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set slots = ['LR0', 'LR3', 'LR4'] %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q,ds=full) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro mac(slot,first=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro load_parts(n,count=3) %}
 {{ at('LR1',n) }}
 {% for slot in slots[:count] %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }}{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(pieces-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds) }} ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro average() %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ load_parts(3) }}
 SET LR10 CR0 ;;
 LD.MULT R0 LR10 {{ cr.crow }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; LD.MULT R0 LR10 {{ cr.crow }} ; INC LR10 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}{{ load(b) }}
 {{ mac('LR0',i==0) }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ;;
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mac('LR0') }} ;;{% endif %}
 {{ save(dest) }}
{% endmacro %}
{% macro reset_chunks() %}
 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
{% endmacro %}
{% macro sum_chunk(ds) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM LR0 {{ ds }} ;;
{% endmacro %}
{% macro center_chunk(ds) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 CR0 ;;
 {{ scalar(first=true,fmt=iq,ds=ds) }} ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {{ scalar('SUB',ds=ds) }}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {{ encode('LR9',3,ds) }}
 INC LR9 1 ;;
{% endmacro %}
{% macro center_parts() %}
 SET LR1 LR9 ;;
 {% for slot in slots %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }}{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro variance_chunk(ds) %}
 {{ center_parts() }}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }}{% if loop.last and i < 2 %} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ;;
{% endmacro %}
{% macro pass_chunks(name,body) %}
 BEQ LR5 LR6 {{ name }}_tail ;;
{{ name }}_full:
 {{ body(full) }}
 INC LR5 1 ;;
 BLT.S LR5 LR6 {{ name }}_full ;;
{{ name }}_tail:
 {{ body(tail) }}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR14 CR0 ;;
 {{ at('LR3',128) }}
 ADD LR4 LR3 LR3 ;;
row_loop:
 ADD LR6 LR14 {{ cr.K }} ;;
 DEC LR6 1 ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }} ;;
 {{ pass_chunks('mean',sum_chunk) }}
 {{ average() }}{{ save(27,3) }}

 {{ reset_chunks() }}
 {{ pass_chunks('center',center_chunk) }}
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }} ;;
 {{ pass_chunks('variance',variance_chunk) }}
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }} ;;
 {{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(22,1) }}

 {# Refine the rsqrt estimate with residual Newton products. #}
 {{ load(8,true) }}{{ load(8) }}{{ mac('LR0',true) }} ;;{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mac('LR0',true) }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ;;{{ save(17) }}
{% macro correct(parts) %}
 {% for n in parts %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }} ;;{% endfor %}
 {{ save(19) }}
{% endmacro %}
 {{ correct([8]) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {{ correct([19,20]) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(21,1) }}

 {{ reset_chunks() }}
 SET LR11 CR0 ;;
affine_loop:
 {{ load_parts(19) }}
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; LD.MULT R0 LR10 {{ cr.gamma }} ; ADD LR10 LR10 {{ cr.K }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(9,3) }}
 {{ center_parts() }}
 {{ load(9) }}
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ; INC LR11 1 ;
 INC LR9 3 ;;
 INC LR5 1 ;;
 BGE.S LR6 LR5 affine_loop ;;

 {# The patches view interleaves groups in input, but stores groups in order. #}
 BGE.S LR2 {{ cr.M }} finish ;;
 ADD LR14 LR14 LR13 ;;
 BLT.S LR14 {{ cr.M }} row_loop ;;
 SUB LR14 LR14 {{ cr.M }} ;;
 ADD LR14 LR14 {{ cr.K }} ; BEQ LR0 CR0 row_loop ;;
finish:
 HALT ;;
