{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(reg,n=0) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1', fmt=q, reduce=false, next='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; {% if reduce %}AGG.SUM LR0 {{ full }}{% else %}ACC.{{ op }}{% if first %}.FIRST{% endif %}{% endif %} {{ next }} ;;
{% endmacro %}
{% macro clear() %}{{ vec(first=true,imm='CR0') }}{% endmacro %}
{% macro mul(first=false,next='',slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} {{ next }} ;;
{% endmacro %}
{% macro load(n,cyclic=false) %}
 {{ at('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{# Consume consecutive residual planes, prefetching the next into R0. #}
{% macro dot(count, first=false, reduce=false) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for j in range(count) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; {% if reduce %}AGG.SUM LR0 {{ full }}{% else %}ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% endif %}{% if not loop.last %} ; LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro add_planes(count,op='ADD',fmt=q,first=false,imm='CR1',base=cr.tmp,step='INC LR1 1') %}
 LD.MULT R0 LR1 {{ base }} ;;
 {% for j in range(count) %}
 {{ vec(op,first and loop.first,imm,fmt,next='; LD.MULT R0 LR1 ' ~ base ~ ' ; ' ~ step if not loop.last else '') }}
 {% endfor %}
{% endmacro %}
{% macro split(reg,count,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for p in range(1,count) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ; INC {{ reg }} 1 ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=2) %}{{ at('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{# AGG leaves the sum in lane zero. Broadcast each residual directly
   from R0 while multiplying by a plane of the reciprocal channel count. #}
{% macro average() %}
 {{ save(0,3) }}
 {% for stat in ['LR0','LR8','LR12'] %}
 LD.MULT.CYCLIC {{ stat }} {{ cr.stats }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% set first_stat = loop.first %}
 {% for next in ['LR8','LR12',''] %}
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first_stat and loop.first %}.FIRST{% endif %}{% if next %} ; LD.MULT R0 {{ next }} {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro added(reduce=false) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR10 LR5 ;;
 {% set fetch = '; LD.MULT R0 LR10 ' ~ cr.addend %}
 {{ vec(first=true,fmt=iq,reduce=reduce,next=fetch) }}
 {% for p in range(3) %}
 {{ vec(reduce=reduce,next=fetch ~ ' ; ADD LR10 LR10 LR13' if not loop.last else '') }}
 {% endfor %}
{% endmacro %}
{% macro reset() %}
 SET LR5 LR2 ;;
 {{ at('LR9',32) }}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ;;
 SET LR8 CR1 ; SET LR12 CR1 ;;
 INC LR12 1 ; SET LR14 CR0 ; SET LR15 CR0 ;;
 INC LR14 128 ; INC LR15 128 ;;
 INC LR15 128 ;;
row_loop:
 ADD LR6 LR2 {{ cr.K }} ; SET LR5 LR2 ;;
 {{ clear() }}
sum_loop:
 {{ added(true) }}
 INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
 {{ average() }}{{ save(6,3) }}

 {{ reset() }}
 DEC LR6 1 ;;
center_loop:
 {{ added() }}
 {{ at('LR1',6) }}{{ add_planes(3,'SUB') }}
 BEQ LR5 LR6 center_tail ;;
  {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ; BEQ LR0 CR0 center_loop ;;
center_tail:
  {{ split('LR9',2,tail) }}

 INC LR6 1 ;;
 {{ reset() }}{{ clear() }}
variance_loop:
 SET LR3 LR9 ;;
  {% for part in range(2) %}
 LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR0 ; SET LR1 LR9 {% if not loop.first %}; INC LR3 1{% endif %} ;;
  {{ dot(2,reduce=true) }}
 {% endfor %}
   INC LR9 2 ; INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
 {{ average() }}
 {{ at('LR1',3) }}
 LD.MULT R0 LR1 {{ cr.stats }} ;;
 {{ vec() }}
 {{ at('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}

 {# Newton: r <- 1.5 r - 0.5 v r^3. #}
 {% for a,b,d,na,nb in [(12,12,14,1,1),(9,14,16,3,2),(12,16,18,1,2)] %}
 SET LR3 CR0 ; SET LR1 CR0 ;;
 {% for i in range(na) %}
 LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR0 ; INC LR3 {{ a if loop.first else 1 }} ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ; {% if loop.first %}INC LR1 {{ b }}{% else %}DEC LR1 1{% endif %} ;;
 {{ mul(first=loop.first,next='; LD.MULT R0 LR1 ' ~ cr.tmp ~ ' ; INC LR1 1' if nb == 2 else '') }}
 {% if nb == 2 %}{{ mul() }}{% endif %}
 {% endfor %}
 {{ save(d) }}
 {% endfor %}
 {{ load(12,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',imm=cr.half) }}{% endfor %}
 {{ save(12) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ; SET LR3 CR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR14 ; DEC LR1 1 ; INC LR3 20 ;;

 {{ reset() }}{{ at('LR11') }}
 DEC LR6 1 ;;
output_loop:
 LD.MULT R0 LR11 {{ cr.gamma }} ; SET LR10 LR11 ;;
 {% for part in range(3) %}
 {{ mul(first=loop.first,slot='LR14') }}
 {{ mul(slot='LR15',next='; LD.MULT R0 LR10 ' ~ cr.gamma ~ ' ; ADD LR10 LR10 ' ~ cr.K if not loop.last else '') }}
 {% endfor %}
  {{ save(20,2) }}
  {% for part in range(2) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; SET LR1 LR3 {% if not loop.first %}; INC LR9 1{% endif %} ;;
  {{ dot(2,first=loop.first) }}
 {% endfor %}
 SET LR1 LR11 ; INC LR9 1 ;;
 {{ add_planes(3,base=cr.beta,step='ADD LR1 LR1 ' ~ cr.K) }}
 BNE LR5 LR6 output_full ;;
 {{ store(tail) }}
 ADD LR2 LR6 CR1 ;;
 BLT.S LR2 LR13 row_loop ;;
 HALT ;;
output_full:
 {{ store(full) }}
 INC LR5 1 ; INC LR11 1 ; BEQ LR0 CR0 output_loop ;;
