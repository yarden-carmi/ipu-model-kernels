{% set nb = s1_n // 128 %}
{% set ke = 8 %}
{% set gb = 34 + (s0_tokens // 128)*ke %}
{% set gs = s1_m*nb %}
{% set tmp = gb+3*gs %}
{% macro num(r,n) %}
 SET {{r}} CR0 ;;
{% if n >= 256 %}
 INC {{r}} {{n//256}} ;;
{% for z in range(8) %}
 ADD {{r}} {{r}} {{r}} ;;
{% endfor %}
{% endif %}
 INC {{r}} {{n%256}} ;;
{% endmacro %}
{% macro at(n) %}
 SET LR13 LR10 ;;
 INC LR13 {{n-tmp}} ;;
{% endmacro %}
{% macro split(n) %}
{{at(n)}}
{% for i in range(3) %}
{% if i %} INC LR13 1 ;; {% endif %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mem}} LR13 ;;
{% if i < 2 %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro prod(a,b,first=false,sub=false) %}
{% for i in range(3) %}
{{at(a+i)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{{at(b)}}
{% for j in range(3) %}
{% if j %} INC LR13 1 ;; {% endif %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sub else 'ADD'}}{{'.FIRST' if first and i==0 and j==0 else ''}} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
{% macro times_c(n) %}
 LD.MULT.CYCLIC LR15 CR0 LR0 ;;
{{at(n)}}
{% for i in range(3) %}
{% if i %} INC LR13 1 ;; {% endif %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{% endmacro %}
 INC LR1 128 ; INC LR11 1 ; INC LR12 {{s0_tokens//128}} ;;
 INC LR13 {{nb}} ;;
 INC LR3 34 ;;
 LD.MULT R1 LR0 {{cr.mem}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for side in range(2) %}
 MULT.VE LR0 {{cr.compare_scale}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k+side) %}
 MULT.VE LR1 {{cr.compare_scale}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 MULT.VE LR1 {{cr.eight}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.mem}} {{'LR0' if side==0 else 'LR11'}} ;;
{% endfor %}
 LD.MULT.CYCLIC LR0 {{cr.mem}} LR0 ;;
 MULT.RC.VV LR0 R1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR11 {{cr.mem}} LR0 ;;
 MULT.RC.VV LR0 R1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 MULT.VE LR1 {{cr.five}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.mem}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR12 decode ;;
 SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR4 CR0 ; SET LR5 CR0 ;;
 INC LR2 34 ;;
token:
 SET LR3 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR3 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 {{cr.mem}} ;;
 LD.MULT.CYCLIC LR7 {{cr.weights}} LR0 ;;
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
{{num('LR12',nb)}}
 BLT.S LR3 LR12 channel ;;
 INC LR5 1 ; INC LR1 1 ;;
{{num('LR12',128)}}
 BLT.S LR1 LR12 no_token_carry ;;
 SET LR1 CR0 ; INC LR2 {{ke}} ;;
no_token_carry:
{{num('LR12',s0_tokens)}}
 BLT.S LR5 LR12 token ;;
 SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR7 CR1 ;;
{{num('LR10',tmp)}}
{{num('LR11',gb)}}
{{num('LR12',gs)}}
norm_row:
 SET LR3 LR2 ; SET LR4 LR2 ;;
 INC LR4 {{nb}} ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
stats:
{% for i in range(3) %}
 SET LR13 LR11 ;;
 ADD LR13 LR13 LR3 ;;
{% for z in range(i) %} ADD LR13 LR13 LR12 ;; {% endfor %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{% for j in range(3) %}
 SET LR13 LR11 ;;
 ADD LR13 LR13 LR3 ;;
{% for z in range(j) %} ADD LR13 LR13 LR12 ;; {% endfor %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
{% endfor %}
{% endfor %}
 INC LR3 1 ;;
 BLT.S LR3 LR4 stats ;;
{{split(tmp)}}
{% for lane in range(2) %}
 SET LR8 CR0 ;;
 INC LR8 {{lane}} ;;
{{at(tmp)}}
{% for i in range(3) %}
{% if i %} INC LR13 1 ;; {% endif %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.EE LR8 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(tmp+3+lane*3)}}
{% endfor %}
{{times_c(tmp+3)}}
{{split(tmp+9)}}
{{times_c(tmp+6)}}
{{prod(tmp+9,tmp+9,sub=true)}}
 LD.MULT R0 LR14 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{at(tmp+15)}}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.mem}} LR13 ;;
{{split(tmp+12)}}
{{at(tmp+15)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{split(tmp+16)}}
{{prod(tmp+12,tmp+16,first=true)}}
{{split(tmp+19)}}
{{at(tmp+15)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{% for i in range(3) %}
{{at(tmp+19+i)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(tmp+22)}}
{{at(tmp+15)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for i in range(3) %}
{{at(tmp+22+i)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{split(tmp+25)}}
 SET LR3 LR2 ; SET LR5 CR0 ;;
norm_out:
 LD.MULT.CYCLIC LR5 {{cr.gamma}} LR0 ;;
{% for i in range(3) %}
{{at(tmp+25+i)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 else ''}} ;;
{% endfor %}
{{split(tmp+28)}}
{% for i in range(3) %}
{{at(tmp+28+i)}}
 LD.MULT.CYCLIC LR13 {{cr.mem}} LR0 ;;
{% for j in range(3) %}
 SET LR13 LR11 ;;
 ADD LR13 LR13 LR3 ;;
{% for z in range(j) %} ADD LR13 LR13 LR12 ;; {% endfor %}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 and j==0 else ''}} ;;
{{at(tmp+9+j)}}
 LD.MULT R0 LR13 {{cr.mem}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{% endfor %}
 LD.MULT.CYCLIC LR5 {{cr.beta}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR3 ;;
 INC LR3 1 ; INC LR5 1 ;;
 BLT.S LR3 LR4 norm_out ;;
 SET LR2 LR4 ; INC LR1 1 ;;
{{num('LR6',s2_rows)}}
 BLT.S LR1 LR6 norm_row ;;
 HALT ;;
