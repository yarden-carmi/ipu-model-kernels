{% set program %}
{% set ke = [s0_vocab, 8]|min %}
{% set ntb = s0_tokens // 128 %}
{% set nb = s1_n // 128 %}
{% set b = (3*ke+2)*ntb %}
{% macro ptr(n) %}
 SET LR1 CR0 ;;
 INC LR1 {{ b+n }} ;;
{% endmacro %}
{% macro load(n,reg='R0') %}
{{ ptr(n) }}
 LD.MULT {{ reg }} LR1 {{ cr.scr }} ;;
{% endmacro %}
{% macro cyc(n,slot='LR0') %}
{{ ptr(n) }}
 LD.MULT.CYCLIC LR1 {{ cr.scr }} {{ slot }} ;;
{% endmacro %}
{% macro store(n,act='identity') %}
{{ ptr(n) }}
 ACTIVATE.QUANTIZE {{ act }} CR0.L {{ cr.qf }}.L {{ cr.scr }} LR1 ;;
{% endmacro %}
{% macro pair(n) %}
{{ store(n) }}
{{ load(n) }}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.SUB ;;
{{ store(n+1) }}
{% endmacro %}
{% macro mul(n,m,first=true) %}
{{ cyc(n) }}
{{ load(m) }}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{{ load(m+1) }}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ cyc(n+1) }}
{{ load(m) }}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endmacro %}
 INC LR3 128 ;;
tb_loop:
 LD.MULT R0 LR2 {{ cr.in0 }} ;;
 LD.MULT R1 LR0 {{ cr.ones }} ;;
 ADD LR4 LR2 CR0 ;;
{% for k in range(ke+1) %}
 MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for z in range(6) %}
 MULT.VE LR3 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
{% for j in range(k) %}
 MULT.VE LR3 {{ cr.sharp }} 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR0.L {{ cr.qf }}.L {{ cr.scr }} LR4 ;;
 INC LR4 {{ntb}} ;;
{% endfor %}
 ADD LR5 LR2 CR0 ;;
{% for k in range(ke+1) %}
 LD.MULT R0 LR5 {{cr.scr}} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
 MULT.VE LR3 {{cr.neg1}} 0 LR0 CR0.L {{cr.qf}}.L ; ACC.MAX ;;
 ACTIVATE.QUANTIZE identity CR0.L {{cr.qf}}.L {{cr.scr}} LR4 ;;
 INC LR4 {{ntb}} ; INC LR5 {{ntb}} ;;
{% endfor %}
 ADD LR5 LR2 CR0 ;;
 INC LR5 {{(ke+1)*ntb}} ;;
 ADD LR6 LR5 CR0 ;;
 INC LR6 {{ntb}} ;;
{% for k in range(ke) %}
 LD.MULT R1 LR5 {{cr.scr}} ;;
 LD.MULT R0 LR6 {{cr.scr}} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR3 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR0.L {{cr.qf}}.L {{cr.scr}} LR4 ;;
 INC LR4 {{ntb}} ; INC LR5 {{ntb}} ;;
 INC LR6 {{ntb}} ;;
{% endfor %}
 INC LR2 1 ;;
 SET LR12 CR0 ;;
 INC LR12 {{ntb}} ;;
 BLT.S LR2 LR12 tb_loop ;;
 SET LR2 CR0 ;;
 SET LR8 CR0 ;;
main_tb:
 SET LR9 CR0 ;;
lane_loop:
{% for j in range(nb) %}
 SET LR11 CR0 ;;
 INC LR11 {{j}} ;;
 ADD LR5 LR2 CR0 ;;
 INC LR5 {{2*(ke+1)*ntb}} ;;
{% for k in range(ke) %}
 LD.MULT.CYCLIC LR11 {{cr.w}} LR0 ;;
 LD.MULT R0 LR5 {{cr.scr}} ;;
 MULT.RC.VE LR0 LR9 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR11 {{nb}} ; INC LR5 {{ntb}} ;;
{% endfor %}
 LD.MULT R0 LR8 {{cr.add0}} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT R0 LR8 {{cr.add1}} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{ pair(2*j) }}
 INC LR8 1 ;;
{% endfor %}
 SET LR7 CR1 ;;
 MULT.VE LR0 CR0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(nb) %}
{{load(2*j)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; AGG.SUM LR0 CR0.L ;;
{{load(2*j+1)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; AGG.SUM LR0 CR0.L ;;
{% endfor %}
{{pair(8)}}
{{load(8)}}
 MULT.EE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(9)}}
 MULT.EE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(10)}}
 LD.MULT.CYCLIC LR0 {{cr.c}} LR0 ;;
{{load(10)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(11)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT.CYCLIC LR14 CR0 LR0 ;;
{{load(10)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(11)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(12)}}
{% for j in range(nb) %}
{{load(2*j)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(2*j+1)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(12)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(13)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(16+2*j)}}
{% endfor %}
 MULT.VE LR0 CR0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(nb) %}
{{cyc(16+2*j)}}
{{load(16+2*j)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; AGG.SUM LR0 CR0.L ;;
{{load(17+2*j)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; AGG.SUM LR0 CR0.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; AGG.SUM LR0 CR0.L ;;
{% endfor %}
{{pair(8)}}
{{load(8)}}
 MULT.EE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(9)}}
 MULT.EE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(10)}}
 LD.MULT.CYCLIC LR0 {{cr.c}} LR0 ;;
{{load(10)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(11)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT.CYCLIC LR14 CR0 LR0 ;;
{{load(10)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(11)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(24)}}
{{load(24)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(25)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{store(26,'rsqrt')}}
{{cyc(26)}}
{{load(26)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{pair(28)}}
{{mul(24,28)}}
{{pair(30)}}
{{cyc(26)}}
{{load(30)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(31)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(32)}}
{# r1 = (3r-r*g)/2 using six constant #}
{{load(26)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for z in range(5) %}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{{load(32)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(33)}}
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(34)}}
{{load(34)}}
 MULT.VE LR0 {{cr.six}} 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(35)}}
 MULT.VE LR0 {{cr.six}} 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(38)}}
{% for j in range(nb) %}
{{mul(16+2*j,38)}}
{{pair(36)}}
 SET LR11 CR0 ;;
 INC LR11 {{j}} ;;
 LD.MULT.CYCLIC LR11 {{cr.gamma}} LR0 ;;
{{load(36)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(37)}}
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT R0 LR11 {{cr.beta}} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR0.L {{cr.qf}}.L {{cr.out0}} LR10 ;;
 INC LR10 1 ;;
{% endfor %}
 INC LR9 1 ;;
 SET LR12 CR0 ;;
 INC LR12 128 ;;
 BLT.S LR9 LR12 lane_loop ;;
 INC LR2 1 ;;
 SET LR12 CR0 ;;
 INC LR12 {{ntb}} ;;
 BLT.S LR2 LR12 main_tb ;;
 HALT ;;
{% endset %}
{{ program | replace('CR0.L', 'CR7.H') }}
