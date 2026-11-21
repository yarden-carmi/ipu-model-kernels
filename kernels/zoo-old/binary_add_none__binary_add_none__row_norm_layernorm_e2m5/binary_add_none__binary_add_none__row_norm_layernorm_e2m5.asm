{% filter replace('CR0.L', cr.qf ~ '.H') %}
{% macro addr(n) %}
 SET LR1 CR0 ;;
{% if n %} INC LR1 {{ n }} ;;
{% endif %}
{% endmacro %}
{% macro save(n) %}
{{ addr(n) }}
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro vec(n, acc='ADD', first=false, scalar='CR1') %}
{% for j in range(2) %}
{{ addr(n+j) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 {{ scalar }} 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.{{ acc }}{% if first and j==0 %}.FIRST{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro prod(a,b,acc='ADD',first=true) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ addr(a+i) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ addr(b+j) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.{{ acc }}{% if first and loop.first %}.FIRST{% endif %} ;;
{% endfor %}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR2 CR0 ;;
 SET LR7 CR1 ;;
 SET LR8 CR0 ;;
 INC LR8 {{ K }} ;;
 LD.MULT R0 LR0 {{ cr.c }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(0) }}
 LD.MULT R0 LR0 {{ cr.C }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(2) }}
{{ prod(0,2) }}
{{ save(4) }}
{{ prod(0,4) }}
{{ save(6) }}
{{ vec(0,first=true) }}
{{ vec(0) }}
{{ vec(6,'SUB') }}
{{ save(8) }}
row_loop:
 SET LR5 CR0 ;;
sum_loop:
{% for name in ['in0','in1','in2'] %}
 LD.MULT R0 LR2 {{ cr[name] }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.xh }} LR5 ;;
 LD.MULT R0 LR5 {{ cr.xh }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.xl }} LR5 ;;
 INC LR2 1 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 sum_loop ;;
 SET LR5 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stat_loop:
 LD.MULT R0 LR5 {{ cr.xh }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.xh }} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR0 CR0.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 LD.MULT R0 LR5 {{ cr.xl }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR0 CR0.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 LD.MULT.CYCLIC LR5 {{ cr.xl }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 stat_loop ;;
{{ save(10) }}
{% for slot,dest in [(0,12),(1,14)] %}
 SET LR6 CR0 ;;
{% if slot %} INC LR6 1 ;;
{% endif %}
{{ addr(10) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.EE LR6 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ addr(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.EE LR6 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(dest) }}
{% endfor %}
{{ prod(12,8) }}
{{ save(16) }}
{{ prod(14,8) }}
{{ prod(16,16,'SUB',false) }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(18) }}
{{ vec(18,first=true) }}
{{ addr(20) }}
 ACTIVATE.QUANTIZE rsqrt CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 INC LR1 1 ;;
 MULT.VE LR0 CR0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{{ prod(20,20) }}
{{ save(22) }}
{{ prod(18,22) }}
{{ save(24) }}
{{ prod(20,24) }}
{{ save(26) }}
{{ vec(20,first=true) }}
{{ vec(20,scalar=cr.half) }}
{{ vec(26,'SUB',scalar=cr.half) }}
{{ save(28) }}
 SET LR5 CR0 ;;
 SET LR10 LR2 ;;
 SUB LR10 LR10 LR8 ;;
out_loop:
 LD.MULT R0 LR5 {{ cr.gamma }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(30) }}
{{ prod(28,30) }}
{{ save(32) }}
 LD.MULT R0 LR5 {{ cr.xh }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR5 {{ cr.xl }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ vec(16,'SUB') }}
{{ save(34) }}
{{ prod(32,34) }}
 LD.MULT R0 LR5 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.out0 }} LR10 ;;
 INC LR10 1 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 out_loop ;;
 BLT.S LR2 LR9 row_loop ;;
 HALT ;;
{% endfilter %}
