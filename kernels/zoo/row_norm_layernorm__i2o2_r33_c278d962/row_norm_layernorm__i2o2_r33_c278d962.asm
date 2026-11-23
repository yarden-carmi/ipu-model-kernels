{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 SET LR1 CR0 {% if n %};;{% else %};{% endif %}
 {% if n %}INC LR1 {{ n }} ; {% endif %}{% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false,next=false) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}{% if next %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(pieces - 1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro average() %}
 {{ save(0,3) }}
 SET LR1 CR0 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for j in range(3) %}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {# Load the reciprocal planes once, then stream the three sum planes. #}
 SET LR7 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.crow }} LR13 ;;
 INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.crow }} LR14 ;;
 SET LR1 CR0 ;;
 INC LR1 3 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR13','LR14'] %}
 {% set plane = loop.index0 %}
 {% for j in range(3) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if plane == 0 and j == 0 %}.FIRST{% endif %}{% if j < 2 %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% elif plane < 2 %} ; DEC LR1 2 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}{{ load(b) }}{{ mul(first=loop.first,next=true) }}
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

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR13 CR0 ;;
 INC LR13 128 ;;
 ADD LR14 LR13 LR13 ;;
 ADD LR15 LR14 LR13 ;;
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
 {{ average() }}{{ save(27,3) }}

 {{ reset_chunks() }}
center_loop:
 SET LR1 CR0 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD.FIRST ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 BNE LR5 LR6 center_full ;;
 {{ encode('LR9',2,tail) }}
 BEQ LR0 CR0 variance_start ;;
center_full:
 {{ encode('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ; BEQ LR0 CR0 center_loop ;;

variance_start:
 INC LR6 1 ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }}
variance_loop:
 SET LR1 LR9 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 {% for rc in ['LR0','LR13'] %}
 MULT.RC.VV {{ rc }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}{% if loop.last and i == 0 %} ; INC LR9 1 ; LD.MULT R0 LR9 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ;;
 {{ next_chunk('variance_loop') }}
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Refine the table estimate with a Newton correction. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true,next=true) }}
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(21,1) }}

 {{ reset_chunks() }}
 SET LR11 CR0 ;;
 {{ at('LR1',19) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR14 ;;
 DEC LR6 1 ;;
output_loop:
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for rc in ['LR0','LR13','LR14'] %}
 MULT.RC.VV {{ rc }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}{% if i < 2 and loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(9,2) }}
 SET LR1 CR0 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR15 ;;
 {% for i in range(2) %}
 {% if i == 0 %}INC LR1 9{% else %}DEC LR1 1{% endif %} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for j in range(2) %}
 MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and j == 0 %}.FIRST{% endif %}{% if j == 0 %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% elif i == 0 %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR15{% else %} ; INC LR9 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 BNE LR5 LR6 output_full ;;
 {{ store(tail) }}
 ADD LR2 LR6 CR1 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
output_full:
 {{ store(full) }}
 INC LR5 1 ; INC LR11 1 ; BEQ LR0 CR0 output_loop ;;
