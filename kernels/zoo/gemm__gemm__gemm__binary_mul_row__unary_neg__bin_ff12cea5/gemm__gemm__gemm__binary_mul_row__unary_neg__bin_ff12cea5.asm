{% macro imm(reg,value) -%}
SET {{reg}} CR0 ;;
{% if value >= 256 %}
INC {{reg}} {{value//256}} ;;
{% for j in range(8) %}ADD {{reg}} {{reg}} {{reg}} ;;
{% endfor %}
{% endif %}
{% if value%256 %}INC {{reg}} {{value%256}} ;;
{% endif %}
{%- endmacro %}
SET LR0 CR0 ;;
{% set ns = [s0_n,s1_n,s2_n] %}
{% set ks = [s0_k,s1_k,s2_k] %}
{% set ms = [s0_m,s1_m,s2_m] %}
{% set bs = [s0_bias,s1_bias,s2_bias] %}
{% set outs = [cr.out0,cr.out1,cr.out2] %}
{% set weightrows = (s0_k*s0_n+s1_k*s1_n+s2_k*s2_n)//128 %}
{% for stage in range(3) %}
{% set n = ns[stage]//128 %}
{% set k = ks[stage]//128 %}
{% set m = ms[stage] %}
{% set offset = namespace(v=0) %}
{% for j in range(stage) %}{% set offset.v = offset.v + ks[j]*ns[j]//128 %}{% endfor %}
{{imm('LR10',n)}}
{{imm('LR11',m)}}
{{imm('LR12',k)}}
SET LR1 CR0 ;;
SET LR7 CR0 ;;
g{{stage}}_head:
SET LR2 CR0 ;;
SET LR8 CR0 ;;
g{{stage}}_m:
{{imm('LR4',offset.v)}}
ADD LR4 LR4 LR1 ;;
SET LR5 LR8 ;;
SET LR6 CR0 ;;
LD.MULT.CYCLIC LR4 {{cr.constants}} LR0 ;;
MULT.RC.VE LR0 CR0 0 LR0 CR8.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
g{{stage}}_kb:
LD.MULT R0 LR5 {{cr.in0}} ;;
SET LR3 CR0 ;;
g{{stage}}_lane:
LD.MULT.CYCLIC LR4 {{cr.constants}} LR0 ;;
MULT.RC.VE LR0 LR3 0 LR0 CR8.H {{cr.qf}}.L ; ACC.ADD ;;
ADD LR4 LR4 LR10 ; INC LR3 1 ;;
BLT.S LR3 {{cr.c128}} g{{stage}}_lane ;;
INC LR5 1 ; INC LR6 1 ;;
BLT.S LR6 LR12 g{{stage}}_kb ;;
{% if bs[stage] %}
{{imm('LR9',weightrows+(ns[:stage]|sum)//128)}}
ADD LR9 LR9 LR1 ;;
LD.MULT.CYCLIC LR9 {{cr.constants}} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR8.H {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR8.H {{cr.qf}}.L {{outs[stage]}} LR7 ;;
INC LR7 1 ; INC LR2 1 ; ADD LR8 LR8 LR12 ;;
BLT.S LR2 LR11 g{{stage}}_m ;;
INC LR1 1 ;;
BLT.S LR1 LR10 g{{stage}}_head ;;
{% endfor %}
{% set opbase = weightrows+(ns|sum)//128 %}
{% for stage in range(2) %}
{% set innerc = s3_inner if stage == 0 else s7_inner %}
{% set inners = s5_inner if stage == 0 else s9_inner %}
{% set offset = opbase if stage == 0 else opbase+(s3_inner+s5_inner)//128 %}
{{imm('LR10',ms[stage]*ns[stage]//128)}}
{{imm('LR11',innerc//128)}}
{{imm('LR9',inners//128)}}
SET LR1 CR0 ;;
SET LR2 CR0 ;;
SET LR3 CR0 ;;
r{{stage}}:
{{imm('LR4',offset)}}
ADD LR4 LR4 LR2 ;;
LD.MULT R0 LR4 {{cr.constants}} ;;
LD.MULT.CYCLIC LR1 {{outs[stage]}} LR0 ;;
MULT.RC.VV LR0 R0 0 LR0 CR8.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity CR8.H {{cr.qf}}.L {{cr.tmp}} LR0 ;;
LD.MULT R0 LR1 {{outs[stage]}} ;;
SET LR12 {{cr.p0}} ;;
SET LR13 {{cr.p1}} ;;
SET LR14 {{cr.p0}} ;;
SET LR15 {{cr.p1}} ;;
ADDBI LRD12 64 ;;
{% for j in range(8) %}
MULT.VE LR0 {{cr.minus_one}} 0 LR0 CR8.H {{cr.qf}}.L ; ACC.RESHAPE LRD12 LRD14 0 ;;
{% if j != 7 %}ADDBI LRD12 8 ; ADDBI LRD14 8 ;;
{% endif %}
{% endfor %}
SET LR12 {{cr.p0}} ;;
SET LR13 {{cr.p1}} ;;
SET LR14 {{cr.p0}} ;;
SET LR15 {{cr.p1}} ;;
ADDBI LRD14 64 ;;
{% for j in range(8) %}
MULT.VE LR0 CR1 0 LR0 CR8.H {{cr.qf}}.L ; ACC.RESHAPE LRD12 LRD14 0 ;;
{% if j != 7 %}ADDBI LRD12 8 ; ADDBI LRD14 8 ;;
{% endif %}
{% endfor %}
SET LR5 CR1 ;;
ACTIVATE.QUANTIZE identity CR8.H {{cr.qf}}.L {{cr.tmp}} LR5 ;;
{{imm('LR4',offset+innerc//128)}}
ADD LR4 LR4 LR3 ;;
LD.MULT R0 LR4 {{cr.constants}} ;;
LD.MULT.CYCLIC LR5 {{cr.tmp}} LR0 ;;
MULT.RC.VV LR0 R0 0 LR0 CR8.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity CR8.H {{cr.qf}}.L {{cr.tmp}} LR5 ;;
LD.MULT.CYCLIC LR0 {{cr.tmp}} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR8.H {{cr.qf}}.L ; ACC.ADD.FIRST ;;
LD.MULT.CYCLIC LR5 {{cr.tmp}} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR8.H {{cr.qf}}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity CR8.H {{cr.qf}}.L {{outs[stage]}} LR1 ;;
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
