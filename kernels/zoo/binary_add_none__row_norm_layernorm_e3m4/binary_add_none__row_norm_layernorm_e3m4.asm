{% macro addr(n) %}
 SET LR1 CR0 ;;
 {% if n %}INC LR1 {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cyc=false) %}
 {{ addr(n) }}
 {% if cyc %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro split(n) %}
 {{ addr(n) }}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro prod(a,b,first=false,sub=false) %}
 {% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
 {{ load(a+i,true) }}{{ load(b+j) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{ 'SUB' if sub else 'ADD' }}{{ '.FIRST' if first and loop.first else '' }} ;;
 {% endfor %}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR2 CR0 ;;
 SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR7 CR1 ;;
add_loop:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 LD.MULT R1 LR2 {{ cr.operand }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR2 {{ cr.M }} add_loop ;;
 SET LR2 CR0 ;;
row_loop:
 SET LR5 LR2 ;;
 ADD LR6 LR2 {{ cr.K }} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
 LD.MULT R0 LR5 {{ cr.out0 }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.out0 }} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 stats ;;
 {{ split(0) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {{ addr(24) }}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 {% for dest,slot in [(2,'LR0'),(4,'LR7')] %}
 {% for n in [0,1,24] %}
 {{ load(n) }}
 MULT.EE {{ slot }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if n == 0 else '' }} ;;
 {% endfor %}
 {{ split(6) }}
 LD.MULT.CYCLIC LR0 {{ cr.invC }} LR0 ;;
 {{ load(6) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(7) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ split(dest) }}
 {% endfor %}
 {{ load(4) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(5) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ prod(2,2,sub=true) }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ addr(10) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 {{ split(8) }}
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ addr(11) }}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 {{ prod(10,10,true) }}{{ split(12) }}
 {{ prod(8,12,true) }}{{ split(14) }}
 {{ prod(10,14,true) }}{{ split(16) }}
 {{ load(10) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {% for n in [16,17] %}
 {{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ split(18) }}
 {{ prod(18,18,true) }}{{ split(12) }}
 {{ prod(8,12,true) }}{{ split(14) }}
 {{ prod(18,14,true) }}{{ split(16) }}
 {% for n in [18,19] %}
 {{ load(n) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {% endfor %}
 {% for n in [16,17] %}
 {{ load(n) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ split(18) }}
 SET LR5 LR2 ;;
 SET LR8 CR0 ;;
outputs:
 LD.MULT.CYCLIC LR8 {{ cr.gamma }} LR0 ;;
 {% for n in [18,19] %}
 {{ load(n) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
 {% endfor %}
 {{ split(20) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {{ addr(25) }}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 {{ prod(2,20,true) }}{{ split(22) }}
 {% for n in [20,21,25] %}
 {{ load(n,true) }}
 LD.MULT R0 LR5 {{ cr.out0 }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if loop.first else '' }} ;;
 {% endfor %}
 {% for n in [22,23] %}
 {{ load(n) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {% endfor %}
 {{ load(25,true) }}
 {% for n in [2,3] %}
 {{ load(n) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {% endfor %}
 LD.MULT R0 LR8 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out1 }} LR5 ;;
 INC LR5 1 ;;
 INC LR8 1 ;;
 BLT.S LR5 LR6 outputs ;;
 SET LR2 LR6 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
