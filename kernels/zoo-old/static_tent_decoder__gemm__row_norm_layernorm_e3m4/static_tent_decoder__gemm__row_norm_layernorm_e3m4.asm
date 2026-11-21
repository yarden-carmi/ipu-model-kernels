{% set ke = [s0_vocab, 8]|min %}
{% set nb = s1_n // 128 %}
{% macro load(row, reg='R0') %}
 SET LR1 CR0 ;;
 INC LR1 {{ row }} ;;
 LD.MULT {{ reg }} LR1 {{ cr.work }} ;;
{% endmacro %}
{% macro cyc(row, slot='LR0') %}
 SET LR1 CR0 ;;
 INC LR1 {{ row }} ;;
 LD.MULT.CYCLIC LR1 {{ cr.work }} {{ slot }} ;;
{% endmacro %}
{% macro pair(row) %}
 SET LR1 CR0 ;;
 INC LR1 {{ row }} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
{% endmacro %}
 INC LR1 128 ; INC LR11 1 ; INC LR12 {{ s0_tokens // 128 }} ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
tokens:
 SET LR10 CR0 ;;
token_lane:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 MULT.EE LR10 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.work }} ;;
{% for k in range(ke) %}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR11 ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{ cr.work }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR1 token_lane ;;
 INC LR2 1 ;;
 BLT.S LR2 LR12 tokens ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
lane:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 {{ cr.selectors }} ;;
 LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
 MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if k == 0 else '' }} ;;
 INC LR6 1 ; INC LR7 {{ nb }} ;;
{% endfor %}
 ADD LR6 LR14 LR8 ;;
 LD.MULT R0 LR6 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ADD LR6 LR15 LR8 ;;
 LD.MULT R0 LR6 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.intermediate }} LR8 ;;
 LD.MULT R0 LR8 {{ cr.intermediate }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 SET LR6 LR8 ;;
 {% for i in range(s1_m * nb // 128) %}
 INC LR6 128 ;;
 {% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.intermediate }} LR6 ;;
 INC LR8 1 ; INC LR5 1 ;;
 SET LR6 CR0 ;;
 INC LR6 {{ nb }} ;;
 BLT.S LR5 LR6 channel ;;
 INC LR2 {{ ke }} ;;
 INC LR4 1 ;;
 BLT.S LR4 LR1 lane ;;
 INC LR9 1 ;;
 BLT.S LR9 LR12 block ;;
 SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
 SET LR7 CR1 ;;
 INC LR3 128 ; INC LR4 128 ;;
 INC LR4 128 ;;
 SET LR12 CR0 ;;
 {% for i in range(s2_rows * nb // 128) %}
 INC LR12 128 ;;
 {% endfor %}
 LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 LD.MULT R0 LR13 CR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ pair(24) }}
 LD.MULT R0 LR0 {{ cr.ones }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(24) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {{ load(25) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {{ pair(26) }}
 {{ load(26) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ pair(28) }}
norm:
 SET LR5 LR2 ; SET LR6 LR2 ;;
 INC LR6 {{ nb }} ;;
 LD.MULT R0 LR0 {{ cr.ones }} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stats:
 LD.MULT R0 LR5 {{ cr.intermediate }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.intermediate }} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
 SET LR10 LR5 ;;
 {% for i in range(s1_m * nb // 128) %}
 INC LR10 128 ;;
 {% endfor %}
 LD.MULT R0 LR10 {{ cr.intermediate }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
 LD.MULT.CYCLIC LR10 {{ cr.intermediate }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; AGG.SUM LR7 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR6 stats ;;
 {{ pair(0) }}
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 SET LR1 CR0 ;;
 INC LR1 30 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
 {% for dest, lane in [(2,'LR0'),(4,'LR7')] %}
 {{ load(0) }}
 MULT.EE {{ lane }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(1) }}
 MULT.EE {{ lane }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ load(30) }}
 MULT.EE {{ lane }} CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ cyc(28) }}
 {{ pair(dest) }}
 {{ load(dest) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(dest+1) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ cyc(29) }}
 {{ load(dest) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ pair(dest+4) }}
 {% endfor %}
 {# mu 6/7; second moment 8/9 #}
 {{ load(8) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(9) }}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ cyc(6) }}
 {{ load(6) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {{ load(7) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 SET LR1 CR0 ;;
 INC LR1 10 ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
 {{ pair(11) }}
 {# Newton r = r0*(1.5 - .5*var*r0*r0), keeping products as pairs #}
 {{ cyc(10) }}
 {{ load(10) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ pair(13) }}
 {{ cyc(11) }}
 {{ load(13) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(14) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ cyc(12) }}
 {{ load(13) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ pair(15) }}
 {{ cyc(10) }}
 {{ load(15) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(16) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ pair(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ load(17) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {{ load(18) }}
 MULT.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {{ pair(19) }}
 SET LR5 LR2 ; SET LR11 CR0 ;;
output:
 LD.MULT.CYCLIC LR11 {{ cr.gamma }} LR0 ;;
 {{ load(19) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 {{ load(20) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {{ pair(21) }}
 LD.MULT R0 LR1 {{ cr.work }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 SET LR1 CR0 ;;
 INC LR1 23 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.work }} LR1 ;;
 LD.MULT.CYCLIC LR5 {{ cr.intermediate }} LR0 ;;
 {{ cyc(6, 'LR3') }}
 {{ cyc(7, 'LR4') }}
 {% for row in [21,22,23] %}
 {{ load(row) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if row == 21 else '' }} ;;
 MULT.RC.VV LR3 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
 {% endfor %}
 SET LR10 LR5 ;;
 {% for i in range(s1_m * nb // 128) %}
 INC LR10 128 ;;
 {% endfor %}
 LD.MULT.CYCLIC LR10 {{ cr.intermediate }} LR0 ;;
 {% for row in [21,22,23] %}
 {{ load(row) }}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 {% endfor %}
 LD.MULT R0 LR11 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR5 ;;
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 output ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR12 norm ;;
 HALT ;;
