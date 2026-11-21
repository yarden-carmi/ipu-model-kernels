{# Scratch pair arithmetic: offsets 0=sum, 2=square sum, 4=reciprocal C,
6=mean, 8=variance, 10=r0, 12=r0 squared, 14=g, 16=r0*g,
18=refined rstd, 20=weight, 22=input-minus-mean, 24=normalised.
LR0=zero, LR1=128, LR2/3=temp addresses, LR4=logical row,
LR5=global chunk, LR6=chunk end, LR7=local chunk.
#}
{% macro idx(reg,n) -%}
SET {{reg}} CR0 ;;
{% for unused in range(n//128) %}INC {{reg}} 128 ;;
{% endfor %}{% if n%128 %}INC {{reg}} {{n%128}} ;;{% endif %}
{%- endmacro %}
{% macro load(n, target='R0') -%}
{{idx('LR2',n)}}
LD.MULT {{target}} LR2 {{cr.tmp}} ;;
{%- endmacro %}
{% macro cyc(n) -%}
{{idx('LR3',n)}}
LD.MULT.CYCLIC LR3 {{cr.tmp}} LR0 ;;
{%- endmacro %}
{% macro pair(n) -%}
{{idx('LR2',n)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
LD.MULT R0 LR2 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
INC LR2 1 ;;
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
LD.MULT R0 LR2 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{idx('LR2',40+n//2)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{% if true %}
LD.MULT R0 LR2 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{idx('LR2',64+n//2)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{% endif %}
{%- endmacro %}
{% macro product(a,b) -%}
{% for i in range(3) %}
{{cyc(a+i if i<2 else 40+a//2)}}
{% for j in range(3) %}
{{load(b+j if j<2 else 40+b//2)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; {{'ACC.ADD.FIRST' if i==0 and j==0 else 'ACC.ADD'}} ;;
{% endfor %}
{% endfor %}
{% if true %}
{{cyc(64+a//2)}}
{{load(b)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
{% if true %}
{{cyc(a)}}
{{load(64+b//2)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
{%- endmacro %}
SET LR0 CR0 ;;
{{idx('LR1',128)}}
{% for name in ['inv','count','ones','eps1','eps2'] %}
LD.MULT R0 LR{{10+loop.index0}} CR0 ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{idx('LR2',35+loop.index0)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{% endfor %}
{% for n in [4,5,42,66] %}
SET LR3 LR{{[11,6,7,8][loop.index0]}} ;;
LD.MULT R0 LR3 CR0 ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{idx('LR2',n)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{% endfor %}
SET LR4 CR0 ;;
SET LR5 CR0 ;;
SET LR14 CR0 ;;
SET LR15 CR0 ;;
gather_row:
SET LR7 CR0 ;;
SET LR8 LR15 ;;
gather_chunk:
SET LR10 CR0 ;;
SET LR11 CR0 ;;
SET LR12 CR0 ;;
SET LR13 CR0 ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{idx('LR9',128)}}
{# LR8 channel address is advanced by a whole chunk at each iteration #}
gather_lane:
LD.MULT R0 LR8 {{cr.in0}} ;;
MULT.EE LR14 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.RESHAPE LRD10 LRD12 0 ;;
ADDBI LRD12 1 ;;
INC LR8 {{input_width}} ;;
DEC LR9 1 ;;
BNE LR9 CR0 gather_lane ;;
LD.MULT R0 LR5 {{cr.operand}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.work}} LR5 ;;
INC LR5 1 ;;
INC LR7 128 ;;
{{idx('LR9',s1_channels)}}
BLT.S LR7 LR9 gather_chunk ;;
INC LR4 1 ;;
INC LR15 1 ;;
{{idx('LR9',input_width)}}
BNE LR15 LR9 gather_next ;;
SET LR15 CR0 ;;
INC LR14 1 ;;
gather_next:
{{idx('LR9',s1_rows)}}
BLT.S LR4 LR9 gather_row ;;

{# Refine c0 using c1 = c0*(2-C*c0). #}
{% if false %}
{{cyc(35)}}
{{load(36)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{pair(28)}}
{{load(37)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(28)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(29)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(54)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(30)}}
{{cyc(35)}}
{{load(30)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(31)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(55)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(4)}}
{# A second reciprocal refinement removes the c0 relative error squared. #}
SET LR4 CR0 ;;
refine_count:
{{cyc(36)}}
{% for n in [4,5,42] %}
{{load(n)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; {{'ACC.ADD.FIRST' if loop.first else 'ACC.ADD'}} ;;
{% endfor %}
{{pair(28)}}
{{load(37)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for n in [28,29,54] %}
{{load(n)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{pair(30)}}
{{product(4,30)}}
{{pair(4)}}
INC LR4 1 ;;
BEQ LR4 CR1 refine_count ;;
{% endif %}

SET LR10 {{cr.gamma1}} ;;
SET LR11 {{cr.beta1}} ;;
SET LR12 {{cr.work}} ;;
SET LR13 {{cr.out0}} ;;
SET LR14 CR0 ;;
norm_start:
SET LR5 CR0 ;;
norm_row:
SET LR6 LR5 ;;
INC LR6 {{s1_channels//128}} ;;
SET LR7 LR5 ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
norm_stat:
ADD LR8 LR7 LR12 ;;
LD.MULT R0 LR8 CR0 ;;
LD.MULT.CYCLIC LR8 CR0 LR0 ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
SET LR9 CR1 ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR9 CR15.L ;;
INC LR7 1 ;;
BLT.S LR7 LR6 norm_stat ;;
{{pair(32)}}
{% for lane, dest in [(0,0),(1,2)] %}
{{load(32)}}
{{idx('LR9',lane)}}
MULT.EE LR9 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(33)}}
MULT.EE LR9 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(56)}}
MULT.EE LR9 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(80)}}
MULT.EE LR9 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(dest)}}
{% endfor %}
{{product(0,4)}}
{{pair(6)}}
{{product(2,4)}}
{{pair(8)}}
{{product(6,6)}}
{{pair(26)}}
{{load(8)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(9)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(44)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(68)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(26)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(27)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(53)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(77)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{idx('LR2',38)}}
ADD LR2 LR2 LR14 ;;
LD.MULT R0 LR2 {{cr.tmp}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{idx('LR2',10)}}
ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{{pair(8)}}
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{idx('LR2',11)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{{idx('LR2',45)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{{idx('LR2',69)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
SET LR15 CR0 ;;
newton:
{{product(10,10)}}
{{pair(12)}}
{{product(8,12)}}
{{pair(14)}}
{{product(10,14)}}
{{pair(16)}}
{% for n in [10,11,45,69] %}
{{load(n)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; {{'ACC.ADD.FIRST' if loop.first else 'ACC.ADD'}} ;;
MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{{load(16)}}
MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(17)}}
MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(48)}}
MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(72)}}
MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(18)}}
{% for a,b in [(18,10),(19,11),(49,45),(73,69)] %}
{{load(a)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{idx('LR2',b)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR2 ;;
{% endfor %}
INC LR15 1 ;;
{{idx('LR9',3)}}
BLT.S LR15 LR9 newton ;;
SET LR7 CR0 ;;
norm_out:
ADD LR8 LR7 LR10 ;;
LD.MULT.CYCLIC LR8 CR0 LR0 ;;
{% for n in [18,19,49,73] %}
{{load(n)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; {{'ACC.ADD.FIRST' if loop.first else 'ACC.ADD'}} ;;
{% endfor %}
{{pair(20)}}
ADD LR8 LR5 LR12 ;;
LD.MULT.CYCLIC LR8 CR0 LR0 ;;
{% for n in [20,21,50,74] %}
{{load(n)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; {{'ACC.ADD.FIRST' if loop.first else 'ACC.ADD'}} ;;
{% endfor %}
{% for m in [6,7,43,67] %}
{{cyc(m)}}
{% for n in [20,21,50,74] %}
{{load(n)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{% endfor %}
ADD LR8 LR7 LR11 ;;
LD.MULT R0 LR8 CR0 ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
ADD LR8 LR5 LR13 ;;
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L CR0 LR8 ;;
INC LR5 1 ;;
INC LR7 1 ;;
BLT.S LR5 LR6 norm_out ;;
{{idx('LR9',s1_rows*s1_channels//128)}}
BLT.S LR5 LR9 norm_row ;;
BNE LR14 CR0 norm_done ;;
SET LR10 {{cr.gamma2}} ;;
SET LR11 {{cr.beta2}} ;;
SET LR12 {{cr.out0}} ;;
SET LR13 {{cr.out1}} ;;
SET LR14 CR1 ;;
BEQ LR0 CR0 norm_start ;;
norm_done:
HALT ;;
