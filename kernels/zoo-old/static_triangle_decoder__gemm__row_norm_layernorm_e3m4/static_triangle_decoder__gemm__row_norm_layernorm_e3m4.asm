{% set nb = s1_n // 128 %}
{% set ke = [s0_vocab,8]|min %}
    INC LR1 128 ; INC LR11 1 ; INC LR12 {{s0_tokens//128}} ;;
    INC LR13 {{nb}} ; INC LR14 128 ;;
    SET LR3 LR15 ;;
    LD.MULT R1 LR0 {{cr.ones}} ;;
tokens:
    LD.MULT R0 LR2 {{cr.in0}} ;;
{% for k in range(ke) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
    MULT.VE LR1 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.MAX ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR0 ;;
    LD.MULT.CYCLIC LR0 {{cr.tmp}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR11 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
    MULT.VE LR1 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for addr in ['LR0','LR11'] %}
    LD.MULT.CYCLIC {{addr}} {{cr.tmp}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L CR0 LR3 ;;
    MULT.VE LR1 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.MAX ;;
    LD.MULT.CYCLIC LR3 CR0 LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    SET LR10 LR3 ;;
    INC LR10 {{s0_tokens//128*ke}} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L CR0 LR10 ;;
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 tokens ;;
    SET LR2 LR15 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR2 ; SET LR7 LR5 ;;
{% for k in range(ke) %}
    LD.MULT R0 LR6 CR0 ;;
    LD.MULT.CYCLIC LR7 {{cr.w}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
    SET LR10 LR6 ;;
    INC LR10 {{s0_tokens//128*ke}} ;;
    LD.MULT R0 LR10 CR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    INC LR6 1 ; INC LR7 {{nb}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mid}} LR8 ;;
    LD.MULT R0 LR8 {{cr.mid}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    SET LR10 LR8 ;;
{% for j in range((s1_m*nb+127)//128) %}
    INC LR10 {{[128,s1_m*nb-j*128]|min}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mid}} LR10 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR13 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR9 1 ; INC LR2 {{ke}} ;;
    BLT.S LR9 LR12 block ;;
{# Arithmetic helpers: high/low XMEM pairs and compensated products. #}
{% macro load(r,addr) %}
    SET LR1 CR0 ;;
    INC LR1 {{addr}} ;;
    LD.MULT {{r}} LR1 {{cr.tmp}} ;;
{% endmacro %}
{% macro cyc(addr) %}
    SET LR1 CR0 ;;
    INC LR1 {{addr}} ;;
    LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
{% endmacro %}
{% macro pair(addr) %}
    SET LR1 CR0 ;;
    INC LR1 {{addr}} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
    LD.MULT R0 LR1 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{% if addr in [20,22] %}
    LD.MULT R0 LR1 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    SET LR1 CR0 ;;
    INC LR1 {{27 if addr==20 else 28}} ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{% endif %}
{% endmacro %}
{% macro prod(a,b,op='ADD',first=false) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{cyc(a+i)}}{{load('R0',b+j)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{op}}{{'.FIRST' if first and loop.first else ''}} ;;
{% endfor %}
{% if a==20 and b==22 %}
{% for aa,bb in [(27,22),(20,28),(27,23),(21,28),(27,28)] %}
{{cyc(aa)}}{{load('R0',bb)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR3 128 ;;
    SET LR7 CR1 ;;
    LD.MULT.CYCLIC LR0 {{cr.crow}} LR0 ;;
    LD.MULT R0 LR0 {{cr.crowC}} ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{pair(20)}}
    LD.MULT R0 LR0 {{cr.ones}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for p in [20,21] %}
{{load('R0',p)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{pair(22)}}
    LD.MULT.CYCLIC LR0 {{cr.crow}} LR0 ;;
{{load('R0',22)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(24)}}
normrow:
    SET LR5 LR2 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{% for k in range(nb) %}
    LD.MULT R0 LR5 {{cr.mid}} ;;
    LD.MULT.CYCLIC LR5 {{cr.mid}} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    SET LR10 LR5 ;;
{% for j in range((s1_m*nb+127)//128) %}
    INC LR10 {{[128,s1_m*nb-j*128]|min}} ;;
{% endfor %}
    LD.MULT R0 LR10 {{cr.mid}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    LD.MULT.CYCLIC LR10 {{cr.mid}} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ;;
{% endfor %}
{{pair(0)}}
    LD.MULT R0 LR1 {{cr.tmp}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    SET LR1 CR0 ;;
    INC LR1 26 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{% for lane,addr in [(0,2),(1,4)] %}
{{load('R0',0)}}{{load('R1',1)}}
    SET LR4 CR0 ;;
    INC LR4 {{lane}} ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    INC LR4 128 ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load('R0',26)}}
    SET LR4 CR0 ;;
    INC LR4 {{lane}} ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(addr)}}
{% endfor %}
{{prod(2,24,first=true)}}{{pair(6)}}
{{prod(4,24,first=true)}}{{prod(6,6,'SUB')}}
    LD.MULT R0 LR0 {{cr.epsilon}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    SET LR1 CR0 ;;
    INC LR1 8 ;;
    ACTIVATE.QUANTIZE rsqrt CR15.L {{cr.qf}}.L {{cr.tmp}} LR1 ;;
{{pair(10)}}
{{cyc(8)}}{{load('R0',8)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{pair(12)}}{{prod(10,12,first=true)}}{{pair(14)}}
{{cyc(8)}}{{load('R0',14)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load('R0',15)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(16)}}
{{cyc(8)}}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for a in [16,17] %}
{{load('R0',a)}}
    MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{pair(18)}}
{{prod(18,18,first=true)}}{{pair(12)}}
{{prod(10,12,first=true)}}{{pair(14)}}
{{prod(18,14,first=true)}}{{pair(16)}}
{% for a in [18,19] %}
{{load('R0',a)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if loop.first else ''}} ;;
    MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{% for a in [16,17] %}
{{load('R0',a)}}
    MULT.VE LR0 {{cr.half}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{pair(18)}}
    SET LR5 LR2 ; SET LR6 CR0 ;;
normout:
    LD.MULT.CYCLIC LR6 {{cr.gamma}} LR0 ;;
{{load('R0',18)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load('R0',19)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(20)}}
    LD.MULT R0 LR5 {{cr.mid}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    SET LR10 LR5 ;;
{% for j in range((s1_m*nb+127)//128) %}
    INC LR10 {{[128,s1_m*nb-j*128]|min}} ;;
{% endfor %}
    LD.MULT R0 LR10 {{cr.mid}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% for a in [6,7] %}
{{load('R0',a)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% endfor %}
{{pair(22)}}{{prod(20,22,first=true)}}
    LD.MULT R0 LR6 {{cr.beta}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR5 ;;
    INC LR5 1 ; INC LR6 1 ;;
    SET LR4 CR0 ;;
    INC LR4 {{nb}} ;;
    BLT.S LR6 LR4 normout ;;
    INC LR2 {{nb}} ;;
    SET LR4 CR0 ;;
{% for j in range((s2_rows*nb+127)//128) %}
    INC LR4 {{[128,s2_rows*nb-j*128]|min}} ;;
{% endfor %}
    BLT.S LR2 LR4 normrow ;;
    HALT ;;
