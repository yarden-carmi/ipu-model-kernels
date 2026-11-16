{% macro imm(r,n) -%}
SET {{r}} CR0 ;;
{% for shift in [24,16,8,0] %}
{% if n >= 2**shift %}
{% if shift<24 and n>=2**(shift+8) %}{% for j in range(8) %}ADD {{r}} {{r}} {{r}} ;;
{% endfor %}{% endif %}
{% if (n//(2**shift))%256 %}INC {{r}} {{(n//(2**shift))%256}} ;;
{% endif %}{% endif %}{% endfor %}{%- endmacro %}
{% macro store(n) -%}
{{imm('LR1',n)}}
ACTIVATE.QUANTIZE identity CR14.H CR14.L {{cr.tmp}} LR1 ;;
{%- endmacro %}
{% macro cyc(n) -%}
{{imm('LR1',n)}}
LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
{%- endmacro %}
{% macro load(n,r='R0') -%}
{{imm('LR1',n)}}
LD.MULT {{r}} LR1 {{cr.tmp}} ;;
{%- endmacro %}
SET LR0 CR0 ;;
SET LR9 CR0 ;;
SET LR10 CR0 ;;
SET LR11 CR0 ;;
{{imm('LR12',s0_rows)}}
norm_row:
MULT.VE LR0 CR0 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
SET LR5 LR11 ;;
SET LR6 CR0 ;;
{{imm('LR7',(s0_rows*2+127)//128)}}
norm_gather:
LD.MULT R0 LR5 {{cr.in0}} ;;
MULT.EE LR10 CR1 0 LR0 CR14.H CR14.L ; AGG.SUM LR6 {{cr.one}}.L ;;
ADD LR5 LR5 LR7 ;;
INC LR6 1 ;;
BLT.S LR6 {{cr.c128}} norm_gather ;;
{{store(8)}}
{{cyc(8)}}
MULT.RC.VS LR0 0 LR0 CR14.H CR14.L ; AGG.SUM.FIRST LR0 CR14.H ;;
{{store(0)}}
{{load(0)}}
MULT.VE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.SUB ;;
{{store(1)}}
{{load(1,'R1')}}
MULT.EE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
{{imm('LR3',128)}}
MULT.EE LR3 CR1 0 LR0 CR14.H CR14.L ; ACC.ADD ;;
{{store(2)}}
{{load(2)}}
MULT.VE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.SUB ;;
{{store(6)}}
{{cyc(2)}}
LD.MULT R0 LR0 {{cr.recip}} ;;
MULT.RC.VV LR0 R0 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
{{cyc(6)}}
MULT.RC.VV LR0 R0 0 LR0 CR14.H CR14.L ; ACC.ADD ;;
LD.MULT R0 LR0 {{cr.epsilon}} ;;
MULT.VE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.ADD ;;
{{imm('LR1',3)}}
ACTIVATE.QUANTIZE rsqrt CR14.H CR14.L {{cr.tmp}} LR1 ;;
{{cyc(8)}}
{{load(3)}}
MULT.RC.VV LR0 R0 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
{{store(4)}}
{{load(4)}}
MULT.VE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.SUB ;;
{{store(5)}}
{{cyc(4)}}
LD.MULT R0 LR0 {{cr.constants}} ;;
MULT.RC.VV LR0 R0 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
{{cyc(5)}}
MULT.RC.VV LR0 R0 0 LR0 CR14.H CR14.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity CR14.H CR14.L {{cr.out0}} LR9 ;;
INC LR9 1 ; INC LR10 1 ;;
BLT.S LR10 {{cr.c128}} norm_same ;;
SET LR10 CR0 ;;
INC LR11 1 ;;
norm_same:
BLT.S LR9 LR12 norm_row ;;
{{imm('LR10',s1_n//128)}}
{{imm('LR11',s1_m)}}
{{imm('LR12',s1_k//128)}}
SET LR1 CR0 ;;
SET LR7 CR0 ;;
g_head:
SET LR2 CR0 ;;
SET LR8 CR0 ;;
g_m:
SET LR4 CR1 ;;
ADD LR4 LR4 LR1 ;;
SET LR5 LR8 ;;
SET LR6 CR0 ;;
LD.MULT.CYCLIC LR4 {{cr.constants}} LR0 ;;
MULT.RC.VE LR0 CR0 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
g_kb:
LD.MULT R0 LR5 {{cr.in1}} ;;
SET LR3 CR0 ;;
g_lane:
LD.MULT.CYCLIC LR4 {{cr.constants}} LR0 ;;
MULT.RC.VE LR0 LR3 0 LR0 CR14.H CR14.L ; ACC.ADD ;;
ADD LR4 LR4 LR10 ; INC LR3 1 ;;
BLT.S LR3 {{cr.c128}} g_lane ;;
INC LR5 1 ; INC LR6 1 ;;
BLT.S LR6 LR12 g_kb ;;
{% if s1_bias %}
{{imm('LR9',1+s1_k*s1_n//128)}}
ADD LR9 LR9 LR1 ;;
LD.MULT.CYCLIC LR9 {{cr.constants}} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.ADD ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR14.H CR14.L {{cr.out1}} LR7 ;;
INC LR7 1 ; INC LR2 1 ; ADD LR8 LR8 LR12 ;;
BLT.S LR2 LR11 g_m ;;
INC LR1 1 ;;
BLT.S LR1 LR10 g_head ;;
{% for stage in range(2) %}
{% set src=cr.out1 if stage==0 else cr.in2 %}
{% set dst=cr.out1 if stage==0 else cr.out2 %}
{% set ic=s2_inner if stage==0 else s6_inner %}
{% set iss=s4_inner if stage==0 else s8_inner %}
{% set offset=1+(s1_k*s1_n+s1_n)//128+(0 if stage==0 else (s2_inner+s4_inner)//128) %}
{{imm('LR10',s1_m*s1_n//128 if stage==0 else s6_numel//128)}}
{{imm('LR11',ic//128)}}
{{imm('LR9',iss//128)}}
SET LR1 CR0 ;;
SET LR2 CR0 ;;
SET LR3 CR0 ;;
r{{stage}}:
{{imm('LR4',offset)}}
ADD LR4 LR4 LR2 ;;
LD.MULT R0 LR4 {{cr.constants}} ;;
LD.MULT.CYCLIC LR1 {{src}} LR0 ;;
MULT.RC.VV LR0 R0 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity CR14.H CR14.L {{cr.tmp}} LR0 ;;
LD.MULT R0 LR1 {{src}} ;;
{% for half in range(2) %}
{{imm('LR12',50462976)}}
{{imm('LR13',117835012)}}
{{imm('LR14',50462976)}}
{{imm('LR15',117835012)}}
ADDBI {{'LRD12' if half==0 else 'LRD14'}} 64 ;;
{% for j in range(8) %}
MULT.VE LR0 {{cr.minus_one if half==0 else 'CR1'}} 0 LR0 CR14.H CR14.L ; ACC.RESHAPE LRD12 LRD14 0 ;;
{% if j!=7 %}ADDBI LRD12 8 ; ADDBI LRD14 8 ;;
{% endif %}{% endfor %}{% endfor %}
SET LR5 CR1 ;;
ACTIVATE.QUANTIZE identity CR14.H CR14.L {{cr.tmp}} LR5 ;;
{{imm('LR4',offset+ic//128)}}
ADD LR4 LR4 LR3 ;;
LD.MULT R0 LR4 {{cr.constants}} ;;
LD.MULT.CYCLIC LR5 {{cr.tmp}} LR0 ;;
MULT.RC.VV LR0 R0 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity CR14.H CR14.L {{cr.tmp}} LR5 ;;
LD.MULT.CYCLIC LR0 {{cr.tmp}} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.ADD.FIRST ;;
LD.MULT.CYCLIC LR5 {{cr.tmp}} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR14.H CR14.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity CR14.H CR14.L {{dst}} LR1 ;;
INC LR2 1 ; INC LR3 1 ;;
BLT.S LR2 LR11 r{{stage}}_c ;;
SET LR2 CR0 ;;
r{{stage}}_c:
BLT.S LR3 LR9 r{{stage}}_s ;;
SET LR3 CR0 ;;
r{{stage}}_s:
INC LR1 1 ;;
BLT.S LR1 LR10 r{{stage}} ;;
{% endfor %}
HALT ;;
