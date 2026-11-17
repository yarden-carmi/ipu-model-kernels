{% set nb=s1_n//128 %}
{% set gb=40+s0_tokens//128*8 %}
{% set gs=s1_m*nb %}
{% macro num(r,n) %}
 SET {{r}} CR0 ;;
 INC {{r}} {{n//256}} ;;
{% for z in range(8) %}
 ADD {{r}} {{r}} {{r}} ;;
{% endfor %}
 INC {{r}} {{n%256}} ;;
{% endmacro %}
{% macro at(n) %}
 SET LR13 CR0 ;;
 INC LR13 {{n}} ;;
{% endmacro %}
{% macro split(n) %}
{{at(n)}}
{% for i in range(3) %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mem}} LR13 ;;
{% if i<2 %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR13 1 ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro prod(a,b,first=false,sub=false) %}
{% for i in range(3) %}
{{at(a+i)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{{at(b)}}
{% for j in range(3) %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sub else 'ADD'}}{{'.FIRST' if first and i==0 and j==0 else ''}} ;;
{% if j<2 %}
 INC LR13 1 ;;
{% endif %}
{% endfor %}
{% endfor %}
{% endmacro %}
{% macro times_c(n) %}
 LD.MULT.CYCLIC LR15 CR0 LR0 ;;
{{at(n)}}
{% for i in range(3) %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
 INC LR13 1 ;;
{% endfor %}
{% endmacro %}
 INC LR7 128 ; INC LR8 1 ;;
 LD.MULT R1 LR0 {{cr.mem}} ;;
 INC LR6 40 ;;
tokens:
 LD.MULT R0 LR5 {{cr.in0}} ;;
{% for k in range(8) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR7 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.mem}} LR8 ;;
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k+1) %}
 MULT.VE LR7 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{% for j in range(6) %}
 MULT.VE LR7 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.mem}} LR0 ;;
 MULT.VE LR7 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.mem}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR8 {{cr.mem}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.mem}} LR6 ;;
 INC LR6 1 ;;
{% endfor %}
 INC LR5 1 ;;
 SET LR12 CR0 ;;
 INC LR12 {{s0_tokens//128}} ;;
 BLT.S LR5 LR12 tokens ;;
 SET LR1 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
 SET LR5 CR0 ;;
 INC LR2 40 ;;
token:
 SET LR3 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR3 ;;
{% for k in range(8) %}
 LD.MULT R0 LR6 {{cr.mem}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
 LD.MULT.CYCLIC LR4 {{cr.add0}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT.CYCLIC LR4 {{cr.add1}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{num('LR13',gb)}}
 ADD LR13 LR13 LR4 ;;
{{num('LR12',gs)}}
{% for i in range(3) %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mem}} LR13 ;;
{% if i<2 %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ADD LR13 LR13 LR12 ;;
{% endif %}
{% endfor %}
 INC LR4 1 ; INC LR3 1 ;;
 SET LR12 CR0 ;;
 INC LR12 {{nb}} ;;
 BLT.S LR3 LR12 channel ;;
 INC LR5 1 ; INC LR1 1 ;;
 SET LR12 CR0 ;;
 INC LR12 128 ;;
 BLT.S LR1 LR12 nocarry ;;
 SET LR1 CR0 ; INC LR2 8 ;;
nocarry:
{{num('LR12',s0_tokens)}}
 BLT.S LR5 LR12 token ;;
 SET LR2 CR0 ; SET LR7 CR1 ;;
{{num('LR11',gb)}}
{{num('LR12',gs)}}
norm:
 SET LR3 LR2 ; SET LR4 LR2 ;;
 INC LR4 {{nb}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
stats:
{% for i in range(3) %}
 SET LR13 LR11 ;;
 ADD LR13 LR13 LR3 ;;
{% for z in range(i) %}
 ADD LR13 LR13 LR12 ;;
{% endfor %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{% for j in range(3) %}
 SET LR13 LR11 ;;
 ADD LR13 LR13 LR3 ;;
{% for z in range(j) %}
 ADD LR13 LR13 LR12 ;;
{% endfor %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
{% endfor %}
{% endfor %}
 INC LR3 1 ;;
 BLT.S LR3 LR4 stats ;;
{{split(2)}}
{% for lane in range(2) %}
 SET LR8 CR0 ;;
 INC LR8 {{lane}} ;;
{% for i in range(3) %}
{{at(2+i)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.EE LR8 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(5+lane*3)}}
{% endfor %}
{{times_c(5)}}
{{split(11)}}
{{times_c(8)}}
{{prod(11,11,sub=true)}}
 LD.MULT R0 LR14 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{at(17)}}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.mem}} LR13 ;;
{{split(14)}}
{{at(17)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{split(18)}}
{{prod(14,18,first=true)}}
{{split(21)}}
{{at(17)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{% for i in range(3) %}
{{at(21+i)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(24)}}
{{at(17)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for i in range(3) %}
{{at(24+i)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{split(27)}}
 SET LR3 LR2 ; SET LR5 CR0 ;;
output:
 LD.MULT.CYCLIC LR5 {{cr.gamma}} LR0 ;;
{% for i in range(3) %}
{{at(27+i)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(30)}}
{% for i in range(3) %}
{{at(30+i)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{% for j in range(3) %}
 SET LR13 LR11 ;;
 ADD LR13 LR13 LR3 ;;
{% for z in range(j) %}
 ADD LR13 LR13 LR12 ;;
{% endfor %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 and j==0 else ''}} ;;
{% endfor %}
{% for j in range(3) %}
{{at(11+j)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{% endfor %}
 LD.MULT R0 LR5 {{cr.beta}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR3 ;;
 INC LR3 1 ; INC LR5 1 ;;
 BLT.S LR3 LR4 output ;;
 SET LR2 LR4 ;;
 BLT.S LR2 LR12 norm ;;
 HALT ;;
