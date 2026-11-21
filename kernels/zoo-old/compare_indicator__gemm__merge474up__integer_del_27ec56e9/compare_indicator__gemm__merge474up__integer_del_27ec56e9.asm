{% set ka = [s0_vocab,8]|min %}
{% set kb = [s3_vocab,9]|min %}
{% set nb = s1_n//128 %}
{% set sa = 32 %}
{% set sb = sa+(s0_tokens//128)*ka %}
{% set xa = sb+(s3_tokens//128)*kb %}
{% set xb = xa+s1_m*nb %}
{% set xx = xb+s1_m*nb %}
{% macro addr(n, lr='LR1') %}
    SET {{lr}} CR0 ;;
{% for j in range((n+254)//255) %}
    INC {{lr}} {{[255,n-j*255]|min}} ;;
{% endfor %}
{% endmacro %}
{% macro load(n, reg='R0') %}
{{addr(n)}}
    LD.MULT {{reg}} LR1 {{cr.mem}} ;;
{% endmacro %}
{% macro cyc(n) %}
{{addr(n)}}
    LD.MULT.CYCLIC LR1 {{cr.mem}} LR0 ;;
{% endmacro %}
{% macro store(n, act='identity') %}
{{addr(n)}}
    ACTIVATE.QUANTIZE {{act}} CR15.L {{cr.qf}}.L {{cr.mem}} LR1 ;;
{% endmacro %}
{% macro pair(n) %}
{{store(n)}}
    LD.MULT R0 LR1 {{cr.mem}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mem}} LR1 ;;
{% endmacro %}
{% macro product(a,b,sign='ADD',first=true) %}
{{cyc(a)}}
{{load(b)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{sign}}{{'.FIRST' if first else ''}} ;;
{{load(b+1)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{sign}} ;;
{{cyc(a+1)}}
{{load(b)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{sign}} ;;
{{load(b+1)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{sign}} ;;
{% endmacro %}
    LD.MULT R1 LR15 CR0 ;;
    SET LR15 CR0 ;;
    INC LR3 128 ;;
    INC LR12 {{s0_tokens//128}} ;;
{{addr(sa,'LR5')}}
{{addr(sb,'LR6')}}
selectors:
{% for path in [0,1] %}
{% for k in range(ka if path==0 else kb) %}
    LD.MULT R0 LR2 {{cr.in0 if path==0 else cr.in1}} ;;
{% if path==0 %}
{% for sign in ['ADD','SUB'] %}
    MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{sign}}.FIRST ;;
{% for j in range(k) %}
    MULT.VE LR3 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.{{'SUB' if sign=='ADD' else 'ADD'}} ;;
{% endfor %}
{{store(0 if sign=='ADD' else 1,'relu6')}}
{% endfor %}
    MULT.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{cyc(0)}}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{cyc(1)}}
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.mem}} LR5 ;;
    INC LR5 1 ;;
{% else %}
{% for boundary in [k,k+1] %}
    MULT.VE LR0 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB.FIRST ;;
    MULT.VE LR3 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{% for j in range(boundary) %}
    MULT.VE LR3 {{cr.sharp}} 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{% endfor %}
{{store(0,'relu6')}}
{{cyc(0)}}
    MULT.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{store(0,'relu')}}
{% if boundary==k %}
    LD.MULT.CYCLIC LR1 {{cr.mem}} LR3 ;;
{% endif %}
{% endfor %}
{{cyc(0)}}
    MULT.RC.VE LR3 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
    ACTIVATE.QUANTIZE relu CR15.L {{cr.qf}}.L {{cr.mem}} LR6 ;;
    INC LR6 1 ;;
{% endif %}
{% endfor %}
{% endfor %}
    INC LR2 1 ;;
    BLT.S LR2 LR12 selectors ;;
    SET LR2 CR0 ; SET LR4 CR0 ;;
    INC LR13 {{nb}} ;;
{{addr(xa,'LR8')}}
{{addr(xb,'LR9')}}
{{addr(xx,'LR10')}}
emb_block:
    SET LR5 CR0 ;;
emb_lane:
    SET LR6 CR0 ;;
emb_channel:
{% for base,ks,w,dst in [(sa,ka,cr.w0,'LR8'),(sb,kb,cr.w1,'LR9')] %}
{{addr(base,'LR7')}}
    ADD LR7 LR7 {{'LR2' if base==sa else 'LR15'}} ;;
    SET LR11 LR6 ;;
{% for k in range(ks) %}
    LD.MULT R0 LR7 {{cr.mem}} ;;
    LD.MULT.CYCLIC LR11 {{w}} LR0 ;;
    MULT.RC.VE LR0 LR5 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD{{'.FIRST' if k==0 else ''}} ;;
    INC LR7 1 ; INC LR11 {{nb}} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mem}} {{dst}} ;;
{% endfor %}
    LD.MULT R0 LR8 {{cr.mem}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR9 {{cr.mem}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mem}} LR10 ;;
    INC LR8 1 ; INC LR9 1 ; INC LR10 1 ;;
    INC LR6 1 ;;
    BLT.S LR6 LR13 emb_channel ;;
    INC LR5 1 ;;
    BLT.S LR5 LR3 emb_lane ;;
    INC LR4 1 ;;
    BLT.S LR4 LR12 next_block ;;
    BEQ LR0 CR0 selector_second ;;
next_block:
    INC LR2 {{ka}} ;;
    INC LR15 {{kb}} ;;
    BEQ LR0 CR0 emb_block ;;
selector_second:
    SET LR2 CR0 ;;
{{addr(xb,'LR8')}}
{{addr(xx,'LR10')}}
    SET LR12 CR0 ;;
    INC LR12 {{s1_m//2}} ;;
    INC LR12 {{s1_m-s1_m//2}} ;;
second_row:
{# Every stored NX8 value has nonzero magnitude, including encoded zero.
   Therefore the fixed vocabulary [0] selector is identically false. #}
    SET LR6 CR0 ;;
second_channel:
    LD.MULT.CYCLIC LR6 {{cr.v}} LR0 ;;
    MULT.RC.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{store(1)}}
    LD.MULT R0 LR1 {{cr.mem}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR10 {{cr.mem}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.mem}} LR10 ;;
    INC LR10 1 ; INC LR6 1 ;;
    BLT.S LR6 LR13 second_channel ;;
    INC LR8 {{nb}} ; INC LR2 1 ;;
    BLT.S LR2 LR12 second_row ;;
    SET LR2 CR0 ; SET LR4 CR0 ; SET LR7 CR1 ;;
{{addr(xx,'LR14')}}
norm:
    SET LR5 LR14 ; SET LR6 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
stats:
    LD.MULT R0 LR5 {{cr.mem}} ;;
    LD.MULT.CYCLIC LR5 {{cr.mem}} LR0 ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR0 CR15.L ;;
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; AGG.SUM LR7 CR15.L ;;
    INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR6 LR13 stats ;;
{{pair(0)}}
{% for slot,dest in [(0,2),(1,4)] %}
    SET LR8 CR0 ;;
    INC LR8 {{slot}} ;;
{{load(0)}}
    MULT.EE LR8 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(1)}}
    MULT.EE LR8 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(dest)}}
    LD.MULT.CYCLIC LR0 {{cr.recip}} LR0 ;;
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
{{store(8,'rsqrt')}}
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
{{load(8)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(14)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{load(15)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.SUB ;;
{{pair(16)}}
{{cyc(30)}}
{{load(16)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
{{load(17)}}
    MULT.RC.VV LR0 R0 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{load(8)}}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD ;;
{{pair(18)}}
    SET LR5 LR14 ; SET LR6 CR0 ;;
outputs:
    LD.MULT R0 LR5 {{cr.mem}} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{cr.qf}}.L ; ACC.ADD.FIRST ;;
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
    ACTIVATE.QUANTIZE identity CR15.L {{cr.qf}}.L {{cr.out0}} LR4 ;;
    INC LR4 1 ; INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR6 LR13 outputs ;;
    INC LR14 {{nb}} ; INC LR2 1 ;;
    BLT.S LR2 LR12 norm ;;
    HALT ;;
