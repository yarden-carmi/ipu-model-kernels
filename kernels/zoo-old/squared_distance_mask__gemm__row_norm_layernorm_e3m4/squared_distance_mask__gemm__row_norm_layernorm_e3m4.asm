{% filter replace('CR15.L','CR14.H') %}
{% set C = s1_n // 128 %}
{% macro store(i) %}
 SET LR1 CR0 ;;
 INC LR1 {{i}} ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{% endmacro %}
{% macro load(i,reg='R0') %}
 SET LR1 CR0 ;;
 INC LR1 {{i}} ;;
 LD.MULT {{reg}} LR1 {{cr.tmp}} ;;
{% endmacro %}
{% macro cyc(i) %}
 SET LR1 CR0 ;;
 INC LR1 {{i}} ;;
 LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
{% endmacro %}
 INC LR3 128 ; INC LR13 {{s0_tokens//128}} ;;
decodeblock:
 LD.MULT R1 LR2 {{cr.in0}} ;;
 SET LR4 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{store(26)}}
 {{store(27)}}
 {{store(31)}}
decode:
 MULT.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for i in [26,27,31] %}
 {{load(i)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 {{store(0)}}
 {{load(0)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(1)}}
 {{cyc(0)}}
 LD.MULT R0 LR0 {{cr.ones}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{load(1)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{cyc(1)}}
 MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.sel}} LR5 ;;
 LD.MULT R0 LR5 {{cr.sel}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(3)}}
 {{load(3)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(5)}}
 {{load(5)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(6)}}
 LD.MULT R0 LR0 {{cr.ones}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR5 {{cr.sel}} ;;
 SET LR11 CR0 ;;
positive_mask:
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 INC LR11 1 ;;
 BLT.S LR11 LR3 positive_mask ;;
 SET LR1 CR0 ;;
 INC LR1 4 ;;
 ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
 {{cyc(4)}}
 {{load(3)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% for i in [5,6] %}
 {{load(i)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 INC LR5 1 ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.sel}} LR5 ;;
 LD.MULT R0 LR0 {{cr.ones}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for i in [26,27,31] %}
 {{load(i)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
 {{store(26)}}
 {{load(26)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(27)}}
 {{load(27)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(31)}}
 INC LR5 1 ; INC LR4 1 ;;
 BLT.S LR4 LR12 decode ;;
 INC LR2 1 ;;
 BLT.S LR2 LR13 decodeblock ;;
 SET LR2 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
block:
 SET LR4 CR0 ;;
token:
{% for c in range(C) %}
 SET LR7 LR5 ; SET LR8 CR0 ;;
 INC LR8 {{c}} ;;
 SET LR9 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
gemm{{c}}:
 LD.MULT R0 LR7 {{cr.sel}} ;;
 LD.MULT.CYCLIC LR8 {{cr.w}} LR0 ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 INC LR7 1 ;;
 LD.MULT R0 LR7 {{cr.sel}} ;;
 MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 INC LR7 1 ; INC LR8 {{C}} ; INC LR9 1 ;;
 BLT.S LR9 LR12 gemm{{c}} ;;
 LD.MULT R0 LR6 {{cr.add}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.x}} LR6 ;;
 LD.MULT R0 LR6 {{cr.x}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 SET LR11 LR6 ;;
{% for z in range(C*s1_m//128) %}
 INC LR11 128 ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.x}} LR11 ;;
 INC LR6 1 ;;
{% endfor %}
 INC LR4 1 ;;
 BLT.S LR4 LR3 token ;;
 ADD LR5 LR5 LR12 ; INC LR2 1 ;;
 ADD LR5 LR5 LR12 ;;
 BLT.S LR2 LR13 block ;;
{# Paired stores preserve residuals for cancellation-sensitive normalization. #}
{% macro pair(i) %}
 {{store(i)}}
 {{load(i)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(i+1)}}
{% endmacro %}
{% macro mul(a,b,first=true,sub=false) %}
{% for ai,bi in [(a,b),(a,b+1),(a+1,b),(a+1,b+1)] %}
 {{cyc(ai)}}
 {{load(bi)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sub else 'ADD'}}{{'.FIRST' if loop.first and first else ''}} ;;
{% endfor %}
{% endmacro %}
 SET LR2 CR0 ; SET LR5 CR0 ; SET LR7 CR1 ;;
 LD.MULT.CYCLIC LR0 {{cr.recip}} LR0 ;;
 LD.MULT R0 LR0 {{cr.channels}} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{pair(20)}}
 LD.MULT R0 LR0 {{cr.ones}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for i in [20,21] %}
 {{load(i)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 {{pair(22)}}
 LD.MULT.CYCLIC LR0 {{cr.recip}} LR0 ;;
 {{load(22)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{load(23)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{pair(24)}}
norm2:
 SET LR6 LR5 ;;
 MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for c in range(C) %}
 LD.MULT R0 LR6 {{cr.x}} ;;
 LD.MULT.CYCLIC LR6 {{cr.x}} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
 SET LR11 LR6 ;;
{% for z in range(C*s1_m//128) %}
 INC LR11 128 ;;
{% endfor %}
 LD.MULT R0 LR11 {{cr.x}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
 LD.MULT.CYCLIC LR11 {{cr.x}} LR0 ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
 INC LR6 1 ;;
{% endfor %}
 {{pair(0)}}
 {{load(1)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
 {{store(30)}}
{% for lane,dest in [(0,2),(1,4)] %}
 {{load(0)}}
{% if lane == 0 %}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% else %}
 MULT.EE LR7 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% endif %}
 {{load(1)}}
 MULT.EE {{'LR0' if lane == 0 else 'LR7'}} CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{load(30)}}
 MULT.EE {{'LR0' if lane == 0 else 'LR7'}} CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{pair(dest)}}
{% endfor %}
 {{mul(2,24)}}
 {{pair(6)}}
 {{mul(4,24)}}
 {{mul(6,6,false,true)}}
 LD.MULT R0 LR14 CR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{pair(8)}}
 {{load(8)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{load(9)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 SET LR1 CR0 ;;
 INC LR1 10 ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
 {{cyc(10)}}
 {{load(10)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{pair(16)}}
 {{mul(8,16)}}
 {{pair(18)}}
 {{cyc(10)}}
 {{load(18)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{load(19)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 {{pair(20)}}
 {{load(10)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for i in [20,21] %}
 {{load(i)}}
 MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 {{pair(28)}}
{% for c in range(C) %}
 LD.MULT R0 LR5 {{cr.x}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 SET LR11 LR5 ;;
{% for z in range(C*s1_m//128) %}
 INC LR11 128 ;;
{% endfor %}
 LD.MULT R0 LR11 {{cr.x}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for i in [6,7] %}
 {{load(i)}}
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
 {{pair(12)}}
 {{mul(12,28)}}
 {{pair(14)}}
 SET LR8 CR0 ;;
 INC LR8 {{c}} ;;
 LD.MULT.CYCLIC LR8 {{cr.gamma}} LR0 ;;
 {{load(14)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
 {{load(15)}}
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 LD.MULT R0 LR8 {{cr.beta}} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR5 ;;
 INC LR5 1 ;;
{% endfor %}
 INC LR2 1 ;;
 BLT.S LR2 LR10 norm2 ;;
 HALT ;;
{% endfilter %}
