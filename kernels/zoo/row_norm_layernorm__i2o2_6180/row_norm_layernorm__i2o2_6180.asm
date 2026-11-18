{% set q = cr.qf_in0 %}
{% macro at(n) %}
 SET LR1 CR0 ;;
 INC LR1 {{ n }} ;;
{% endmacro %}
{% macro load(n,cy=false,slot='LR0') %}
 {{ at(n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% endif %}
{% endmacro %}
{% macro mul(op='ADD',first=false,slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }}.L ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro scalar(op='ADD') %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.{{ op }} ;;
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at(n) }}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }}.L {{ cr.tmp }} LR1 ;;
 {% if i+1 < pieces %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}
 INC LR1 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {{ load(a,true) }}
 {{ load(b) }}{{ mul(first=true) }}
 {{ load(b+1) }}{{ mul() }}
 {{ load(a+1,true) }}
 {{ load(b) }}{{ mul() }}
 {{ save(dest) }}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
 SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR4 LR3 ;;
 INC LR4 128 ;;
 SET LR7 CR1 ;;
 SET LR13 CR0 ;;
 INC LR13 129 ;;
row_loop:
 SET LR5 LR2 ;;
 ADD LR6 LR2 {{ cr.K }} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
stat_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR7 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 stat_loop ;;
 {{ save(0) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}
 {{ save(26,1) }}
 {% for idx,dest in [(0,2),(1,4)] %}
 {{ load(0) }}
 {{ at(1) }}
 LD.MULT R1 LR1 {{ cr.tmp }} ;;
 MULT.EE {% if idx==0 %}LR0{% else %}LR7{% endif %} CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 MULT.EE {% if idx==0 %}LR3{% else %}LR13{% endif %} CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {{ load(26) }}
 MULT.EE {% if idx==0 %}LR0{% else %}LR7{% endif %} CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {{ save(dest) }}
 {% endfor %}
 {% for src,dest in [(2,6),(4,-1)] %}
 LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 {{ load(src) }}{{ mul(first=true) }}
 {{ load(src+1) }}{{ mul() }}
 LD.MULT.CYCLIC LR7 {{ cr.crow }} LR0 ;;
 {{ load(src) }}{{ mul() }}
 {{ load(src+1) }}{{ mul() }}
 {% if dest >= 0 %}{{ save(dest) }}{% endif %}
 {% endfor %}
 {{ load(6,true,'LR3') }}
 {{ load(6) }}{{ mul('SUB',slot='LR3') }}
 {{ load(7) }}{{ mul('SUB',slot='LR3') }}{{ mul('SUB',slot='LR3') }}
 {{ load(7,true,'LR3') }}{{ mul('SUB',slot='LR3') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}
 {{ at(8) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }}.L {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 {{ load(8,true) }}
 {{ load(8) }}{{ mul(first=true) }}
 {{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}
 {{ load(15) }}{{ mul(first=true) }}
 {{ load(16) }}{{ mul() }}
 {{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR13 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {% for n in [17,18] %}
 {{ load(n) }}
 MULT.VE LR0 CR13 0 LR0 CR15.L {{ q }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}
 {{ product(11,13,15) }}
 {{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 CR13 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}
 {{ load(n) }}
 MULT.VE LR0 CR13 0 LR0 CR15.L {{ q }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ save(19) }}
 SET LR5 LR2 ;;
 SET LR11 CR0 ;;
out_loop:
 ADD LR10 LR11 LR11 ;;
 ADD LR10 LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {{ load(19) }}{{ mul(first=loop.first) }}
 {{ load(20) }}{{ mul() }}
 INC LR10 1 ;;
 {% endfor %}
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
 {{ load(6,true,'LR3') }}
 {{ load(7,true,'LR4') }}
 {% for n in [9,10,11] %}
 {{ load(n) }}{{ mul(first=loop.first) }}
 {{ mul('SUB',slot='LR3') }}{{ mul('SUB',slot='LR4') }}
 {% endfor %}
 ADD LR10 LR11 LR11 ;;
 ADD LR10 LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar() }}
 INC LR10 1 ;;
 {% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 INC LR5 1 ;;
 INC LR11 1 ;;
 BLT.S LR5 LR6 out_loop ;;
 ADD LR2 LR2 {{ cr.K }} ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
