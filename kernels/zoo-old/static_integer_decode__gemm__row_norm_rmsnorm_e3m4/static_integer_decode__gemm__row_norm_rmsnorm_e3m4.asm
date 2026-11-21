{% set ke = [s0_vocab,8]|min %}
{% set nb = s1_n//128 %}
{% set nt = s0_tokens//128 %}
{% macro pair(r) %}
 SET LR1 CR0 ;;
 INC LR1 {{r}} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{% endmacro %}
 INC LR10 128 ;;
 SET LR11 CR1 ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
{% for b in [k,k+1] %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
{% for j in range(b) %}
 MULT.VE LR10 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.tmp}} LR11 ;;
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR0 ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.tmp}} LR11 ;;
{% if loop.first %}
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR10 ;;
{% endif %}
{% endfor %}
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.sel}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 SET LR12 CR0 ;;
 INC LR12 {{nt}} ;;
 BLT.S LR2 LR12 decode ;;
 SET LR2 CR0 ;;
block:
 SET LR4 CR0 ;;
token:
 SET LR5 CR0 ;;
channel:
 SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
 LD.MULT R0 LR6 {{cr.sel}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
 INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
{% if s1_bias %}
 LD.MULT R0 LR5 {{cr.bias}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
 LD.MULT R1 LR0 {{cr.ones}} ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR5 ;;
 INC LR5 1 ;;
 SET LR13 CR0 ;;
 INC LR13 {{nb}} ;;
 BLT.S LR5 LR13 channel ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR5 CR0 ;;
stat:
 LD.MULT.CYCLIC LR5 {{cr.work}} LR0 ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR13 stat ;;
{{pair(0)}}
 LD.MULT R0 LR0 {{cr.tmp}} ;;
 LD.MULT R1 LR11 {{cr.tmp}} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.EE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(2)}}
 SET LR1 CR0 ;;
 INC LR1 2 ;;
 LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
 LD.MULT R0 LR0 {{cr.recip}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 INC LR1 1 ;;
 LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT R0 LR0 {{cr.epsilon}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
 SET LR5 CR0 ;;
output:
 LD.MULT.CYCLIC LR5 {{cr.work}} LR0 ;;
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(4)}}
 SET LR6 CR0 ;;
 INC LR6 4 ;;
 LD.MULT.CYCLIC LR6 {{cr.tmp}} LR0 ;;
 LD.MULT R0 LR5 {{cr.gamma}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 INC LR6 1 ;;
 LD.MULT.CYCLIC LR6 {{cr.tmp}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 SET LR1 CR0 ;;
 INC LR1 3 ;;
 BLT.S LR5 LR13 output ;;
 INC LR4 1 ;;
 BLT.S LR4 LR10 token ;;
 INC LR9 1 ; INC LR2 {{ke}} ;;
 BLT.S LR9 LR12 block ;;
 HALT ;;
