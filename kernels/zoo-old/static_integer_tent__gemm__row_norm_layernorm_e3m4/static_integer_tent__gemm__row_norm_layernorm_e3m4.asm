{% set ke = [s0_vocab,8]|min %}
{% set nb = s1_n//128 %}
{% macro ix(r) %}
 SET LR1 CR0 ;;
 INC LR1 {{r}} ;;
{% endmacro %}
{% macro save(r,n=2) %}
{% for i in range(n) %}
{{ix(r+i)}}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{% if not loop.last %}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endif %}
{% endfor %}
{% endmacro %}
{% macro loadsum(r,n=2) %}
{% for i in range(n) %}
{{ix(r+i)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
{% endmacro %}
{% macro prod(a,b,n=2) %}
{% for i in range(n) %}
{{ix(a+i)}}
 LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
{% for j in range(n) %}
{{ix(b+j)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if i==0 and j==0 else ''}} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
 INC LR10 128 ;;
 SET LR11 CR1 ;;
 LD.MULT R1 LR0 {{cr.ones}} ;;
decode:
 LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k+1) %}
 MULT.VE LR10 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.tmp}} LR0 ;;
 MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
 MULT.VE LR10 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 ACTIVATE.QUANTIZE relu6 CR15.L {{cr.qf}}.L {{cr.tmp}} LR11 ;;
 MULT.VE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT.CYCLIC LR0 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 LD.MULT.CYCLIC LR11 {{cr.tmp}} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.sel}} LR3 ;;
 INC LR3 1 ;;
{% endfor %}
 INC LR2 1 ;;
 SET LR12 CR0 ;;
 INC LR12 {{s0_tokens//128}} ;;
 BLT.S LR2 LR12 decode ;;
 # Refine reciprocal channel count, tmp 28/29.
 LD.MULT.CYCLIC LR0 {{cr.recip}} LR0 ;;
 LD.MULT R0 LR14 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{save(0)}}
 LD.MULT R0 LR0 {{cr.ones}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for r in [0,1] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{save(2)}}
 LD.MULT.CYCLIC LR0 {{cr.recip}} LR0 ;;
{% for r in [2,3] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{save(28)}}
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
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR5 ;;
 INC LR5 1 ;;
 SET LR15 CR0 ;;
 INC LR15 {{nb}} ;;
 BLT.S LR5 LR15 channel ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR5 CR0 ;;
stats:
 LD.MULT R0 LR5 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR15 stats ;;
{{save(0,3)}}
{% for r in range(3) %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
{{save(2)}}
{{prod(2,28)}}
{{save(4)}}
 # Variance by centered differences, stored as pairs per channel.
 SET LR5 CR0 ;;
center:
 LD.MULT R0 LR5 {{cr.work}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for r in [4,5] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR5 ;;
{{save(6)}}
 SET LR6 LR5 ;;
 INC LR6 16 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR6 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR15 center ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR5 CR0 ;;
variance:
 LD.MULT.CYCLIC LR5 {{cr.work}} LR0 ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 SET LR6 LR5 ;;
 INC LR6 16 ;;
 LD.MULT R0 LR6 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR15 variance ;;
{{save(0,3)}}
{% for r in range(3) %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
{{save(2)}}
{{prod(2,28)}}
 LD.MULT R0 LR13 {{cr.tmp}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{ix(8)}}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{{save(10)}}
{{prod(8,8,1)}}
{{save(12)}}
{{prod(10,12)}}
{{save(14)}}
{{ix(8)}}
 LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
{% for r in [14,15] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
{{save(20)}}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for r in [20,21] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{save(22)}}
 SET LR5 CR0 ;;
output:
 LD.MULT.CYCLIC LR5 {{cr.gamma}} LR0 ;;
{% for r in [22,23] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
{{save(24)}}
 LD.MULT.CYCLIC LR5 {{cr.work}} LR0 ;;
{% for r in [24,25] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
{% endfor %}
 SET LR6 LR5 ;;
 INC LR6 16 ;;
 LD.MULT.CYCLIC LR6 {{cr.tmp}} LR0 ;;
{% for r in [24,25] %}
{{ix(r)}}
 LD.MULT R0 LR1 {{cr.tmp}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 LD.MULT R0 LR5 {{cr.beta}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR8 ;;
 INC LR8 1 ; INC LR5 1 ;;
 BLT.S LR5 LR15 output ;;
 INC LR4 1 ;;
 BLT.S LR4 LR10 token ;;
 INC LR9 1 ; INC LR2 {{ke}} ;;
 BLT.S LR9 LR12 block ;;
 HALT ;;
