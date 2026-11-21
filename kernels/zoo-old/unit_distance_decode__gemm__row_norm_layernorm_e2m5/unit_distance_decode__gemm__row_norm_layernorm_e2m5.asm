{% set ke = [s0_vocab,8]|min %}
{% set nb = s1_n // 128 %}
{# tmp pair helpers; LR0 is zero, LR1 address scratch, LR3=128 #}
{% macro load(row, reg='R0') %}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    LD.MULT {{ reg }} LR1 {{ cr.tmp }} ;;
{% endmacro %}
{% macro cyc(row) %}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{% endmacro %}
{% macro pair(row) %}
    SET LR1 CR0 ;;
    INC LR1 {{ row }} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro product(a,b,sign='ADD',first=true) %}
{{ cyc(a) }}
{{ load(b) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{sign}}{{'.FIRST' if first else ''}} ;;
{{ load(b+1) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{sign}} ;;
{{ cyc(a+1) }}
{{ load(b) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{sign}} ;;
{{ load(b+1) }}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.{{sign}} ;;
{% endmacro %}
    INC LR1 128 ; INC LR12 {{s0_tokens//128}} ; INC LR13 {{nb}} ;;
    INC LR14 128 ;;
    LD.MULT R1 LR0 {{cr.ones}} ;;
tokens:
{% for k in range(ke) %}
    LD.MULT R0 LR2 {{cr.in0}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR0 ;;
    LD.MULT R0 LR0 {{cr.tmp}} ;;
    MULT.VE LR0 {{cr.negative}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR0 ;;
    LD.MULT R0 LR0 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.sel}} LR3 ;;
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
    LD.MULT R0 LR6 {{cr.sel}} ;;
    LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
    INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
    LD.MULT R0 LR8 {{cr.add}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.x}} LR8 ;;
    LD.MULT R0 LR8 {{cr.x}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    SET LR10 LR8 ;;
{% for j in range((s1_m*nb+254)//255) %}
    INC LR10 {{ [255,s1_m*nb-j*255]|min }} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.x}} LR10 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR9 1 ; INC LR2 {{ke}} ;;
    BLT.S LR9 LR12 block ;;
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR7 CR1 ;;
    SET LR13 CR0 ;;
    INC LR3 128 ;;
    SET LR12 CR0 ;;
    INC LR12 {{s2_rows//2}} ;;
    INC LR12 {{s2_rows-s2_rows//2}} ;;
    SET LR14 CR0 ;;
    INC LR14 {{nb}} ;;
norm:
    SET LR5 LR2 ; SET LR6 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
stats:
    LD.MULT R0 LR5 {{cr.x}} ;;
    LD.MULT.CYCLIC LR5 {{cr.x}} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    SET LR10 LR5 ;;
{% for j in range((s1_m*nb+254)//255) %}
    INC LR10 {{ [255,s1_m*nb-j*255]|min }} ;;
{% endfor %}
    LD.MULT R0 LR10 {{cr.x}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    LD.MULT.CYCLIC LR10 {{cr.x}} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR6 LR14 stats ;;
{{pair(0)}}
{% for slot, dest in [(0,2),(1,4)] %}
    SET LR8 CR0 ;;
    INC LR8 {{slot}} ;;
{{load(0)}}
    MULT.EE LR8 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(1)}}
    MULT.EE LR8 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    LD.MULT.CYCLIC LR0 {{cr.recip}} LR0 ;;
{{pair(dest)}}
{{load(dest)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(dest+1)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(dest)}}
{% endfor %}
{{load(4)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(5)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{product(2,2,'SUB',false)}}
    LD.MULT R0 LR0 {{cr.epsilon}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 8 ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{{pair(6)}}
{{cyc(8)}}
{{load(8)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{pair(10)}}
{{product(6,10)}}
{{pair(12)}}
{{cyc(8)}}
{{load(12)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(13)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(14)}}
{# r = r0 + (r0 - r0*g)/2; use ones scaled by exact 0.5 scratch #}
{{load(8)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(14)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(15)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(16)}}
    SET LR1 CR0 ;;
    INC LR1 30 ;;
    LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
{{load(16)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(17)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(8)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(18)}}
    SET LR5 LR2 ; SET LR6 CR0 ;;
outputs:
    LD.MULT R0 LR5 {{cr.x}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    SET LR10 LR5 ;;
{% for j in range((s1_m*nb+254)//255) %}
    INC LR10 {{ [255,s1_m*nb-j*255]|min }} ;;
{% endfor %}
    LD.MULT R0 LR10 {{cr.x}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(2)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(3)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(20)}}
{{product(20,18)}}
{{pair(22)}}
    LD.MULT.CYCLIC LR6 {{cr.gamma}} LR0 ;;
{{load(22)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(23)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    LD.MULT R0 LR6 {{cr.beta}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    SET LR1 LR15 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L CR0 LR1 ;;
    INC LR15 1 ; INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR6 LR14 outputs ;;
    INC LR2 {{nb}} ; INC LR13 1 ;;
    BLT.S LR13 LR12 norm ;;
    HALT ;;
