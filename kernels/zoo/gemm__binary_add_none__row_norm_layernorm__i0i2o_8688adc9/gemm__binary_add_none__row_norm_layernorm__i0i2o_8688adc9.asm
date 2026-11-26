{% set q = cr.qf_in0 ~ '.L' %}
{% set qr = cr.qf_in1 ~ '.L' %}
{% set ds = 'CR15.L' %}
{% set root = cr.scalar ~ '.H' %}
{% set work = cr.scalar ~ '.L' %}
{% set aq = cr.affine_qf ~ '.L' %}
{% set slots = ['LR0','LR5','LR6','LR7'] %}
{% set parts = 4 %}
{% set xp = 5 if s0_k % 128 else parts %}
{% macro seek(r,n) %}
SET {{r}} CR0 ;;
{% for i in range(n//255) %}INC {{r}} 255 ;;{% endfor %}
{% if n%255 %}INC {{r}} {{n%255}} ;;{% endif %}
{% endmacro %}
{% macro v(op='ADD',e='',fmt=work) %}
MULT.VE LR0 CR1 0 LR0 {{ds}} {{fmt}} ; ACC.{{op}} {{e}} ;;
{% endmacro %}
{% macro vv(slot,op='ADD',e='',fmt=work) %}
MULT.RC.VV {{slot}} R0 0 LR0 {{ds}} {{fmt}} ; ACC.{{op}} {{e}} ;;
{% endmacro %}
{% macro st(r,fmt=work,act='identity') %}ACTIVATE.QUANTIZE {{act}} {{ds}} {{fmt}} {{cr.tmp}} {{r}}{% endmacro %}
{% macro ld(n,slot='') %}
{{seek('LR1',n)}}
{% if slot %}LD.MULT.CYCLIC LR1 {{cr.tmp}} {{slot}} ;;{% else %}LD.MULT R0 LR1 {{cr.tmp}} ;;{% endif %}
{% endmacro %}
{% macro split(r,p=parts) %}
{{st(r)}} ;;
{% for i in range(p-1) %}
LD.MULT R0 {{r}} {{cr.tmp}} ;;
{{v('SUB','; INC '~r~' 1 ; '~st(r))}}
{% endfor %}
{% endmacro %}
{% macro split_at(n,p=parts) %}{{seek('LR1',n)}}{{split('LR1',p)}}{% endmacro %}
{% macro start() %}
SET LR11 {{cr.config}}.L ; SET LR10 CR0 ;;
INC LR10 40 ;;
{% endmacro %}
{% macro clear() %}MULT.VE LR0 CR0 0 LR0 {{ds}} {{work}} ; ACC.ADD.FIRST ;;{% endmacro %}
{% macro mul(a,b,na=parts,nb=parts,first=true) %}
{% for j in range(nb) %}{{ld(b+j,slots[j])}}{% endfor %}
{{ld(a)}}
{% for i in range(na) %}
{% for j in range(nb) %}
{{vv(slots[j],'ADD.FIRST' if first and i==0 and j==0 else 'ADD','; INC LR1 1 ; LD.MULT R0 LR1 '~cr.tmp if loop.last and i+1<na else '')}}
{% endfor %}
{% endfor %}
{% endmacro %}
{# A lane is a token; each weight scalar updates all 128 tokens. #}
SET LR0 CR0 ; SET LR8 CR0 ; SET LR12 {{cr.config}}.H ;;
SET LR14 CR0 ; DEC LR8 1 ;;
{{seek('LR4',125)}}
{{seek('LR5',128)}}
ADD LR6 LR5 LR5 ;;
ADD LR7 LR5 LR6 ;;
{{seek('LR13',3)}}
{{seek('LR1',34)}}
{% for i in range(6) %}
LD.MULT R0 LR13 {{cr.crow}} {% if i %}; INC LR1 1 ; INC LR13 1{% endif %} ;;
{{v('ADD.FIRST','; '~st('LR1'),q)}}
{% endfor %}
block:
{{start()}}
SET LR9 LR14 ; SET LR15 CR0 ;;
DEC LR15 1 ;;
channel:
LD.MULT R0 LR9 {{cr.in1}} ;;
{{v('ADD.FIRST','; LD.MULT R0 LR15 '~cr.w~' ; INC LR15 1',qr)}}
{{v(fmt=q,e='; LD.MULT R0 LR15 '~cr.w~' ; INC LR15 1')}}
{{v(fmt=q,e='; LD.MULT R0 LR15 '~cr.w~' ; INC LR15 1 ; SUB LR2 LR14 LR12')}}
{% for chunk in range((s0_k+127)//128) %}
{% set count = [s0_k-128*chunk,128]|min %}
SET LR3 LR8 ; LD.MULT.CYCLIC LR2 {{cr.in0}} LR0 ; ADD LR2 LR2 LR12 ;;
{% if count > 1 %}
{% if count < 128 %}DEC LR4 {{128-count}} ;;{% endif %}
k_{{chunk}}:
MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{q}} ; ACC.ADD ; INC LR3 1 ; LD.MULT.CYCLIC LR2 {{cr.in0}} LR0 ; ADD LR2 LR2 LR12 ; BLT.S LR3 LR4 k_{{chunk}} ;;
{% endif %}
MULT.RC.VE LR0 LR3 0 LR0 {{ds}} {{q}} ; ACC.ADD ; INC LR3 1 {% if not loop.last %}; LD.MULT R0 LR15 {{cr.w}} ; INC LR15 1{% endif %} ;;
{% if 1 < count and count < 128 %}INC LR4 {{128-count}} ;;{% endif %}
{% endfor %}
{{split('LR10',xp)}}
INC LR10 1 ; ADD LR9 LR9 LR12 ; DEC LR11 1 ; BLT.S CR1 LR11 channel ;;

{# Mean and centered variance use compensated FP8 expansions. #}
{{start()}}
{{clear()}}
sum:
LD.MULT R0 LR10 {{cr.tmp}} ;;
{% for i in range(xp) %}
{{v(e='; INC LR10 1' ~ (' ; LD.MULT R0 LR10 '~cr.tmp if not loop.last else ' ; DEC LR11 1 ; BLT.S CR1 LR11 sum'))}}
{% endfor %}
{{split_at(0)}}
{{mul(0,34)}}
{{mul(0,38,parts,2,false)}}
{{split_at(6)}}
{% for i in range(parts) %}{{ld(6+i,slots[i])}}{% endfor %}
{{start()}}
center:
LD.MULT R0 LR10 {{cr.tmp}} ; SET LR1 LR10 ;;
{% for i in range(xp) %}
{{v('ADD.FIRST' if loop.first else 'ADD','; INC LR10 1 ; LD.MULT R0 LR10 '~cr.tmp if not loop.last else '')}}
{% endfor %}
{% for i in range(parts) %}
MULT.RC.VE {{slots[i]}} CR1 0 LR0 {{ds}} {{work}} ; ACC.SUB ;;
{% endfor %}
{{split('LR1',xp)}}
INC LR10 1 ; DEC LR11 1 ; BLT.S CR1 LR11 center ;;
{{start()}}
{{clear()}}
variance:
{% for i in range(parts) %}
{% if i %}INC LR10 1 ; {% endif %}LD.MULT.CYCLIC LR10 {{cr.tmp}} {{slots[i]}} ;;
{% endfor %}
{% for i in range(parts) %}
MULT.RC.VS {{slots[i]}} 0 LR0 {{ds}} {{work}} ; ACC.ADD ;;
{% endfor %}
{% if xp > parts %}
INC LR10 1 ; LD.MULT R0 LR10 {{cr.tmp}} ;;
{% for slot in slots %}{{vv(slot)}}{{vv(slot)}}{% endfor %}
LD.MULT.CYCLIC LR10 {{cr.tmp}} LR7 ;;
MULT.RC.VS LR7 0 LR0 {{ds}} {{work}} ; ACC.ADD ; DEC LR10 1 ;;
LD.MULT.CYCLIC LR10 {{cr.tmp}} LR7 ;;
{% endif %}
{% for i in range(parts-1,0,-1) %}
LD.MULT R0 LR10 {{cr.tmp}} ;;
{% for j in range(i) %}
{{vv(slots[j])}}{{vv(slots[j],e='; DEC LR10 1' if loop.last else '')}}
{% endfor %}
{% endfor %}
INC LR10 {{xp}} ; DEC LR11 1 ; BLT.S CR1 LR11 variance ;;
{{split_at(0)}}
{{mul(0,34)}}
{{mul(0,38,parts,2,false)}}
SET LR13 CR0 ; LD.MULT R0 LR13 {{cr.crow}} ;;
{{v(fmt=q)}}
{{seek('LR1',10)}}
{{st('LR1',root,'rsqrt')}} ;;
{{split_at(17)}}
{{ld(10)}}
{{v('ADD.FIRST',fmt=root)}}
{{split_at(11)}}
{# Newton correction r <- r * (1.5 - 0.5 * variance * r^2). #}
{{seek('LR3',2)}}
refine:
{{mul(17,11)}}
{{split_at(21)}}
{{mul(11,21)}}
{{split_at(25)}}
SET LR13 CR0 ;;
INC LR13 2 ; LD.MULT R0 LR13 {{cr.crow}} ;;
{{seek('LR1',33)}}
{{v('ADD.FIRST',e='; '~st('LR1'),fmt=q)}}
LD.MULT.CYCLIC LR1 {{cr.tmp}} LR7 ;;
LD.MULT R0 LR13 {{cr.crow}} ; DEC LR13 1 ;;
{{v('ADD.FIRST',fmt=q)}}
{% for i in range(parts) %}
{{ld(25+i)}}
{{vv('LR7','SUB')}}
{% endfor %}
{{split_at(29)}}
{{mul(11,29)}}
{{split_at(11)}}
DEC LR3 1 ; BLT.S CR1 LR3 refine ;;
{{ld(11,'LR5')}}{{ld(12,'LR6')}}

{{start()}}
SET LR9 LR14 ; SET LR13 CR0 ;;
normalize:
{{ld(13,'LR7')}}
LD.MULT R0 LR10 {{cr.tmp}} ;;
{% for i in range(xp) %}
{{vv('LR5','ADD.FIRST' if loop.first else 'ADD')}}
{{vv('LR7')}}
{{vv('LR6',e='; INC LR10 1' ~ (' ; LD.MULT R0 LR10 '~cr.tmp if not loop.last else ''))}}
{% endfor %}
{% if s0_k % 128 %}
{{ld(14,'LR7')}}
DEC LR10 {{xp}} ;;
{% for i in range(xp) %}
LD.MULT R0 LR10 {{cr.tmp}} ;;
{{vv('LR7',e='; INC LR10 1')}}
{% endfor %}
{% endif %}
{{seek('LR1',15)}}
{{st('LR1',aq)}} ;;
LD.MULT R0 LR1 {{cr.tmp}} ;;
{{v('SUB','; INC LR1 1 ; '~st('LR1',aq),aq)}}
LD.MULT.CYCLIC LR1 {{cr.tmp}} LR7 ;;
DEC LR1 1 ; LD.MULT.CYCLIC LR1 {{cr.tmp}} LR0 ;;
LD.MULT R0 LR13 {{cr.affine}} ;;
{% set ap = 3 if s0_k % 128 else 2 %}
{% for i in range(ap) %}
{{vv('LR0','ADD.FIRST' if loop.first else 'ADD',fmt=aq)}}
{{vv('LR7',e='; INC LR13 1 ; LD.MULT R0 LR13 '~cr.affine,fmt=aq)}}
{% endfor %}
{% for i in range(ap) %}
{{v(e='; INC LR13 1 ; '~('ACTIVATE.QUANTIZE '~(act_out0|default('identity'))~' '~ds~' '~cr.qf_out0~'.L '~cr.out0~' LR9' if loop.last else 'LD.MULT R0 LR13 '~cr.affine),fmt=aq)}}
{% endfor %}
ADD LR9 LR9 LR12 ; DEC LR11 1 ; BLT.S CR1 LR11 normalize ;;
INC LR14 1 ;;
BLT.S LR14 LR12 block ;;
HALT ;;
