{% set original = cr %}
{% set cr = dict(in0=original.in0,w='P_w',ones=original.ones,work='S_tmp',selectors='S_sel',out0='S_mid',sharp=original.sharp,qf=original.qf) %}
{% set first %}
    INC LR1 128 ; INC LR12 {{ s0_tokens // 128 }} ; INC LR14 128 ;;
    INC LR15 {{ s1_n // 128 }} ;;
    INC LR13 {{ ke }} ;;
    LD.MULT R1 LR0 {{ cr.ones }} ;;
token_block:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% for k in range(ke) %}
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR0 ;;
    MULT.VE LR0 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR1 {{ cr.sharp }} 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
{% endfor %}
    SET LR6 CR1 ;;
    ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf }}.L {{ cr.work }} LR6 ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR0 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    LD.MULT.CYCLIC LR6 {{ cr.work }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf }}.L {{ cr.selectors }} LR3 ;;
    INC LR3 1 ;;
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 token_block ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
block:
    SET LR4 CR0 ;;
lane:
    SET LR5 CR0 ;;
channel:
    SET LR6 LR3 ; SET LR7 LR5 ; SET LR9 CR0 ;;
    MULT.VE LR1 CR0 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
dot:
    LD.MULT R0 LR6 {{ cr.selectors }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    INC LR6 1 ; INC LR7 {{ K }} ; INC LR9 1 ;;
    BLT.S LR9 LR13 dot ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD ;;
    MULT.VE LR1 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; INC LR5 1 ;;
    BLT.S LR5 LR15 channel ;;
    INC LR4 1 ;;
    BLT.S LR4 LR14 lane ;;
    INC LR3 {{ ke }} ;;
    INC LR2 1 ;;
    BLT.S LR2 LR12 block ;;
{% endset %}
{% set cr = dict(in0='S_mid',in1='P_a',in2='P_b',out0=original.out0,gamma='P_g',beta='P_bet',tmp='S_tmp',xh='S_xh',xl='S_xl',c=original.c,C=original.C,epsilon=original.epsilon,qf=original.qf,half=original.half,M='LR9') %}
{% set second %}
{% filter replace('CR0.L', cr.qf ~ '.H') %}
{% macro addr(n) %}
 SET LR1 CR0 ;;
{% if n %} INC LR1 {{ n }} ;;
{% endif %}
{% endmacro %}
{% macro save(n) %}
{{ addr(n) }}
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.SUB ;;
 INC LR1 1 ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% macro vec(n, acc='ADD', first=false, scalar='CR1') %}
{% for j in range(2) %}
{{ addr(n+j) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.VE LR0 {{ scalar }} 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.{{ acc }}{% if first and j==0 %}.FIRST{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro prod(a,b,acc='ADD',first=true) %}
{% for i,j in [(0,0),(0,1),(1,0),(1,1)] %}
{{ addr(a+i) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ addr(b+j) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.{{ acc }}{% if first and loop.first %}.FIRST{% endif %} ;;
{% endfor %}
{% endmacro %}
 SET LR0 CR0 ;;
 SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR2 CR0 ;;
 SET LR7 CR1 ;;
 SET LR8 CR0 ;;
 INC LR8 {{ K }} ;;
 LD.MULT R0 LR0 {{ cr.c }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(0) }}
 LD.MULT R0 LR0 {{ cr.C }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(2) }}
{{ prod(0,2) }}
{{ save(4) }}
{{ prod(0,4) }}
{{ save(6) }}
{{ vec(0,first=true) }}
{{ vec(0) }}
{{ vec(6,'SUB') }}
{{ save(8) }}
row_loop:
 SET LR5 CR0 ;;
sum_loop:
{% for name in ['in0','in1','in2'] %}
 LD.MULT R0 LR2 {{ cr[name] }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
{% endfor %}
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.xh }} LR5 ;;
 LD.MULT R0 LR5 {{ cr.xh }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.SUB ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.xl }} LR5 ;;
 INC LR2 1 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 sum_loop ;;
 SET LR5 CR0 ;;
 MULT.VE LR0 CR0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
stat_loop:
 LD.MULT R0 LR5 {{ cr.xh }} ;;
 LD.MULT.CYCLIC LR5 {{ cr.xh }} LR0 ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR0 CR0.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 LD.MULT R0 LR5 {{ cr.xl }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR0 CR0.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 LD.MULT.CYCLIC LR5 {{ cr.xl }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 CR0.L {{ cr.qf }}.L ; AGG.SUM LR7 CR0.L ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 stat_loop ;;
{{ save(10) }}
{% for slot,dest in [(0,12),(1,14)] %}
 SET LR6 CR0 ;;
{% if slot %} INC LR6 1 ;;
{% endif %}
{{ addr(10) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.EE LR6 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ addr(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.EE LR6 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(dest) }}
{% endfor %}
{{ prod(12,8) }}
{{ save(16) }}
{{ prod(14,8) }}
{{ prod(16,16,'SUB',false) }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ save(18) }}
{{ vec(18,first=true) }}
{{ addr(20) }}
 ACTIVATE.QUANTIZE rsqrt CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
 INC LR1 1 ;;
 MULT.VE LR0 CR0 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.tmp }} LR1 ;;
{{ prod(20,20) }}
{{ save(22) }}
{{ prod(18,22) }}
{{ save(24) }}
{{ prod(20,24) }}
{{ save(26) }}
{{ vec(20,first=true) }}
{{ vec(20,scalar=cr.half) }}
{{ vec(26,'SUB',scalar=cr.half) }}
{{ save(28) }}
 SET LR5 CR0 ;;
 SET LR10 LR2 ;;
 SUB LR10 LR10 LR8 ;;
out_loop:
 LD.MULT R0 LR5 {{ cr.gamma }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
{{ save(30) }}
{{ prod(28,30) }}
{{ save(32) }}
 LD.MULT R0 LR5 {{ cr.xh }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
 LD.MULT R0 LR5 {{ cr.xl }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
{{ vec(16,'SUB') }}
{{ save(34) }}
{{ prod(32,34) }}
 LD.MULT R0 LR5 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 CR0.L {{ cr.qf }}.L ; ACC.ADD ;;
 ACTIVATE.QUANTIZE identity CR0.L {{ cr.qf }}.L {{ cr.out0 }} LR10 ;;
 INC LR10 1 ;;
 INC LR5 1 ;;
 BLT.S LR5 LR8 out_loop ;;
 BLT.S LR2 LR9 row_loop ;;
 HALT ;;
{% endfilter %}
{% endset %}
{% set mid = 40 + s0_tokens // 128 * ke %}
{% set offsets = dict(P_w=0,P_a=0,P_b=0,P_g=0,P_bet=K,S_tmp=0,S_sel=40,S_mid=mid,S_xh=mid+M,S_xl=mid+M+K) %}
{% set combined = first | replace('HALT ;;','') | replace('CR15.L',original.qf ~ '.H') %}
{% set reset %}
{% for i in range(16) %}
SET LR{{i}} CR0 ;;
{% endfor %}
{% for chunk in range(M // 255) %} INC LR9 255 ;;
{% endfor %}
INC LR9 {{ M % 255 }} ;;
{% endset %}
{% for line in (combined ~ reset ~ second).split('\n') %}
{% set words = line.split() %}
{% set ns = namespace(text=line, pre='', post='') %}
{% for word in words %}
{% if word in offsets %}
{% set idx = words.index(word) %}
{% set reg = words[idx+1] if 'ACTIVATE.QUANTIZE' in words else words[idx-1] %}
{% set off = offsets[word] %}
{% set base = original.packed if word.startswith('P_') else original.space %}
{% if word == 'P_a' %}{% set base = original.a %}{% endif %}
{% if word == 'P_b' %}{% set base = original.b %}{% endif %}
{% if word in ['P_g','P_bet'] %}{% set base = original.g %}{% endif %}
{% set ns.text = ns.text | replace(word,base) %}
{% if off %}
{% for chunk in range(off // 255) %}
{% set ns.pre = ns.pre ~ '\nINC ' ~ reg ~ ' 255 ;;' %}
{% set ns.post = ns.post ~ '\nDEC ' ~ reg ~ ' 255 ;;' %}
{% endfor %}
{% set ns.pre = ns.pre ~ '\nINC ' ~ reg ~ ' ' ~ (off % 255) ~ ' ;;' %}
{% set ns.post = ns.post ~ '\nDEC ' ~ reg ~ ' ' ~ (off % 255) ~ ' ;;' %}
{% endif %}
{% endif %}
{% endfor %}
{{ns.pre}}
{{ns.text}}
{{ns.post}}
{% endfor %}
