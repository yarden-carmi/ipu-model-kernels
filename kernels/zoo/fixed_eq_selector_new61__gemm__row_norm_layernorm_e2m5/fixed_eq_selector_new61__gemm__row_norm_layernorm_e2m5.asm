{% set ke = [s0_vocab,8]|min %}
{% set nb = s1_n//128 %}
{% macro split(n) %}
 SET LR1 CR0 ;;
 INC LR1 {{n}} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR1 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR1 ;;
{% endmacro %}
 INC LR1 128 ; INC LR11 1 ; INC LR12 {{s0_tokens//128}} ;;
 INC LR13 {{nb}} ; INC LR14 128 ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
tokens:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} LR0 ;;
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR1 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.work}} LR11 ;;
 MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{cr.work}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.selectors}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
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
 LD.MULT R0 LR6 {{cr.selectors}} ;;
 LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
 INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mid}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR13 channel ;;
 INC LR4 1 ;;
 BLT.S LR4 LR14 lane ;;
 INC LR9 1 ; INC LR2 {{ke}} ;;
 BLT.S LR9 LR12 block ;;
{% for i in range(15) %}
 SET LR{{i}} CR0 ;;
{% endfor %}
 INC LR3 128 ; INC LR4 128 ; INC LR7 1 ;;
 INC LR4 128 ; SET LR12 LR15 ;;
normrow:
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for c in range(nb) %}
 LD.MULT R0 LR2 {{cr.mid}} ;;
 LD.MULT.CYCLIC LR2 {{cr.mid}} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
 INC LR2 1 ;;
{% endfor %}
{{split(0)}}
 LD.MULT.CYCLIC LR0 {{cr.inv}} LR0 ;;
{% for dest, laneidx in [(2,0),(4,1)] %}
 SET LR1 CR0 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 INC LR1 1 ;;
 LD.MULT R1 LR1 {{cr.work}} ;;
 SET LR5 CR0 ;;
 INC LR5 {{laneidx}} ;;
 SET LR6 LR3 ;;
 INC LR6 {{laneidx}} ;;
 MULT.EE LR5 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.EE LR6 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{split(6)}}
 SET LR1 CR0 ;;
 INC LR1 6 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{split(dest)}}
{% endfor %}
 SET LR1 CR0 ;;
 INC LR1 4 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 SET LR1 CR0 ;;
 INC LR1 2 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR3 ;;
 MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT R0 LR0 {{cr.epsilon}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 SET LR1 CR0 ;;
 INC LR1 8 ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.work}} LR1 ;;
{{split(12)}}
 SET LR1 CR0 ;;
 INC LR1 8 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{split(14)}}
 SET LR1 CR0 ;;
 INC LR1 12 ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR0 ;;
{% for p in range(2) %}
 SET LR1 CR0 ;;
 INC LR1 {{14+p}} ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if p==0 else ''}} ;;
{% endfor %}
 SET LR1 CR0 ;;
 INC LR1 13 ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR0 ;;
 SET LR1 CR0 ;;
 INC LR1 14 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{split(16)}}
 SET LR1 CR0 ;;
 INC LR1 8 ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR0 ;;
{% for p in range(2) %}
 SET LR1 CR0 ;;
 INC LR1 {{16+p}} ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if p==0 else ''}} ;;
{% endfor %}
{{split(18)}}
 SET LR1 CR0 ;;
 INC LR1 31 ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR4 ;;
 SET LR1 CR0 ;;
 INC LR1 8 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for p in range(2) %}
 SET LR1 CR0 ;;
 INC LR1 {{18+p}} ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{split(20)}}
 SET LR11 CR0 ;;
{% for c in range(nb) %}
 LD.MULT.CYCLIC LR11 {{cr.gamma}} LR0 ;;
 SET LR1 CR0 ;;
 INC LR1 20 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{split(10)}}
 LD.MULT.CYCLIC LR8 {{cr.mid}} LR0 ;;
 SET LR1 CR0 ;;
 INC LR1 3 ;;
 LD.MULT.CYCLIC LR1 {{cr.work}} LR4 ;;
{% for p in range(2) %}
 SET LR1 CR0 ;;
 INC LR1 {{10+p}} ;;
 LD.MULT R0 LR1 {{cr.work}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if p==0 else ''}} ;;
 MULT.RC.VV LR3 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 LD.MULT R0 LR11 {{cr.beta}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR11 1 ;;
{% endfor %}
 BLT.S LR2 LR12 normrow ;;
 HALT ;;
