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
{% macro save(n,pieces=2,ds='CR15') %}
 {{ at(n) }}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ ds }}.L {{ q }}.L {{ cr.tmp }} LR1 ;;
 {% if i+1 < pieces %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}
 INC LR1 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {{ load(a,true) }}{{ load(b) }}{{ mul(first=true) }}
 {{ load(b+1) }}{{ mul() }}
 {{ load(a+1,true) }}{{ load(b) }}{{ mul() }}
 {{ save(dest) }}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
 SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR7 CR1 ;;
row_loop:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR0 {{ cr.active }}.L ;;
 {{ save(0) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(26,1) }}
 {{ load(0) }}{{ at(1) }}
 LD.MULT R1 LR1 {{ cr.tmp }} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 MULT.EE LR3 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {{ load(26) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {{ save(2,3) }}
 LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 {{ load(2) }}{{ mul(first=true) }}
 {{ load(3) }}{{ mul() }}
 LD.MULT.CYCLIC LR7 {{ cr.crow }} LR0 ;;
 {{ load(2) }}{{ mul() }}{{ load(3) }}{{ mul() }}
 LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 {{ load(4) }}{{ mul() }}
 {{ save(6,3) }}
 {{ load(8) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 {{ save(30,1) }}
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 {% for n in [6,7,30] %}
 {{ load(n) }}{{ scalar('SUB') }}
 {% endfor %}
 {{ save(28,2,cr.active) }}
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 {% for a,b in [(28,28),(28,29),(29,28),(29,29)] %}
 {{ load(a,true) }}{{ load(b) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }}.L ; AGG.SUM LR0 {{ cr.active }}.L ;;
 {% endfor %}
 {{ save(0,3) }}
 {% for n in [0,1,2] %}
 {{ load(n) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(4) }}
 LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 {{ load(4) }}{{ mul(first=true) }}{{ load(5) }}{{ mul() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}{{ at(8) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }}.L {{ cr.tmp }} LR1 ;;
 {{ save(11) }}{{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}{{ load(16) }}{{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {% for n in [17,18] %}
 {{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}
 {{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ save(19) }}
 SET LR10 CR0 ;;
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {{ load(19) }}{{ mul(first=loop.first) }}{{ load(20) }}{{ mul() }}
 INC LR10 1 ;;
 {% endfor %}
 {{ save(9,3) }}
 {{ load(28,true) }}{{ load(29,true,'LR3') }}
 {% for n in [9,10,11] %}
 {{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}
 {% endfor %}
 SET LR10 CR0 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar() }}
 INC LR10 1 ;;
 {% endfor %}
 ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
