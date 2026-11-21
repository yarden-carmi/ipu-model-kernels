{% macro imm(reg,n) -%}
SET {{reg}} CR0 ;;
{% for i in range(n//128) %}INC {{reg}} 128 ;;
{% endfor %}{% if n%128 %}INC {{reg}} {{n%128}} ;;
{% endif %}
{%- endmacro %}
{% macro store(n) -%}
{{imm('LR1',n)}}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{%- endmacro %}
{% macro cyc(n) -%}
{{imm('LR1',n)}}
LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
{%- endmacro %}
{% macro load(n,reg='R0') -%}
{{imm('LR1',n)}}
LD.MULT {{reg}} LR1 {{cr.tmp}} ;;
{%- endmacro %}
SET LR0 CR0 ;;
SET LR9 CR0 ;;
SET LR10 CR0 ;;
SET LR11 CR0 ;;
{{imm('LR12',s0_rows)}}
norm_row:
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
SET LR5 LR11 ;;
SET LR6 CR0 ;;
{{imm('LR7',(s0_rows+127)//128)}}
norm_gather:
LD.MULT R0 LR5 {{cr.in0}} ;;
MULT.EE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR6 {{cr.one}}.L ;;
ADD LR5 LR5 LR7 ;;
INC LR6 1 ;;
BLT.S LR6 {{cr.c128}} norm_gather ;;
{{store(8)}}
{{cyc(8)}}
MULT.RC.VS LR0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
{{store(0)}}
{{load(0)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{store(1)}}
{{load(1,'R1')}}
MULT.EE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{imm('LR3',128)}}
MULT.EE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{store(2)}}
{{load(2)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{store(6)}}
{{cyc(2)}}
LD.MULT R0 LR0 {{cr.recip}} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{cyc(6)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
LD.MULT R0 LR0 {{cr.epsilon}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{imm('LR1',3)}}
ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{{cyc(8)}}
{{load(3)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{store(4)}}
{{load(4)}}
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{store(5)}}
{{cyc(4)}}
LD.MULT R0 LR0 {{cr.gamma}} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{cyc(5)}}
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR9 ;;
INC LR9 1 ; INC LR10 1 ;;
BLT.S LR10 {{cr.c128}} norm_same ;;
SET LR10 CR0 ;;
INC LR11 1 ;;
norm_same:
BLT.S LR9 LR12 norm_row ;;
SET LR2 CR0 ;;
SET LR11 CR0 ;;
SET LR5 CR0 ;;
SET LR7 CR0 ;;
{{imm('LR13',s1_m)}}
{{imm('LR14',s1_n//128)}}
m_loop:
SET LR6 CR0 ;;
nb_loop:
SET LR4 LR6 ;;
SUB LR4 LR4 LR14 ;;
SET LR8 LR11 ;;
SUB LR8 LR8 CR1 ;;
LD.MULT.CYCLIC LR6 {{cr.w}} LR2 ;;
MULT.RC.VE LR2 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
SET LR9 CR0 ;;
kb_loop:
LD.MULT R0 LR8 {{cr.in1}} ; INC LR8 1 ;;
SET LR3 CR0 ;;
SUB LR3 LR3 CR1 ;;
{% for i in range(4) %}
LD.MULT.CYCLIC LR4 {{cr.w}} LR2 ; ADD LR4 LR4 LR14 ; INC.MODP2 LR2 {{cr.c128}} 9 ;;
{% endfor %}
{% for i in range(124) %}
MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{cr.w}} LR2 ; ADD LR4 LR4 LR14 ; INC LR3 1 ; INC.MODP2 LR2 {{cr.c128}} 9 ;;
{% endfor %}
{% for i in range(4) %}
MULT.RC.VE LR2 LR3 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ; INC LR3 1 ; INC.MODP2 LR2 {{cr.c128}} 9 ;;
{% endfor %}
INC LR9 1 ;;
{{imm('LR10',s1_k//128)}}
BLT.S LR9 LR10 kb_loop ;;
{% if s1_bias %}
ADD LR4 LR15 LR6 ;;
LD.MULT.CYCLIC LR4 CR0 LR2 ;;
MULT.RC.VE LR2 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.gx}} LR7 ;;
LD.MULT R0 LR7 {{cr.gx}} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{imm('LR4',s1_m*(s1_n//128))}}
ADD LR4 LR4 LR7 ;;
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.gx}} LR4 ;;
INC LR7 1 ; INC LR6 1 ;;
BLT.S LR6 LR14 nb_loop ;;
ADD LR11 LR11 LR10 ;;
INC LR5 1 ;;
BLT.S LR5 LR13 m_loop ;;
SET LR2 CR0 ;;
SET LR7 CR0 ;;
SET LR9 CR0 ;;
SET LR10 CR0 ;;
{{imm('LR12',s1_n)}}
transpose_n:
SET LR8 CR0 ;;
SET LR5 LR9 ;;
transpose_block:
MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
SET LR6 CR0 ;;
transpose_m:
LD.MULT R0 LR5 {{cr.gx}} ;;
MULT.EE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR6 {{cr.one}}.L ;;
{{imm('LR4',s1_m*(s1_n//128))}}
ADD LR4 LR4 LR5 ;;
LD.MULT R0 LR4 {{cr.gx}} ;;
MULT.EE LR10 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR6 {{cr.one}}.L ;;
ADD LR5 LR5 LR14 ;;
INC LR6 1 ; INC LR8 1 ;;
BGE.S LR8 LR13 transpose_store ;;
BLT.S LR6 {{cr.c128}} transpose_m ;;
transpose_store:
ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out1}} LR7 ;;
INC LR7 1 ;;
BLT.S LR8 LR13 transpose_block ;;
INC LR10 1 ;;
BLT.S LR10 {{cr.c128}} transpose_lane ;;
SET LR10 CR0 ;;
INC LR9 1 ;;
transpose_lane:
INC LR2 1 ;;
BLT.S LR2 LR12 transpose_n ;;
HALT ;;
