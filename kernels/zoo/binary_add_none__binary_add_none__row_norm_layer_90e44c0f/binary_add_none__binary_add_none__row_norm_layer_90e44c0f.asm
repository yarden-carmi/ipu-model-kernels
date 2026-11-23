{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set aligned = s2_channels % 128 == 0 %}
{% macro at(reg,n=0) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1', fmt=q, reduce=false, next='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; {% if reduce %}AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ full }}{% else %}ACC.{{ op }}{% if first %}.FIRST{% endif %}{% endif %} {{ next }} ;;
{% endmacro %}
{% macro clear() %}{{ vec(first=true,imm='CR0') }}{% endmacro %}
{% macro mul(first=false,next='',slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} {{ next }} ;;
{% endmacro %}
{# Consume consecutive residual planes, prefetching the next into R0. #}
{% macro dot(count, first=false, reduce=false,setup='',finish='') %}
 LD.MULT R0 LR1 {{ cr.tmp }} {{ setup }} ;;
 {% for j in range(count) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; {% if reduce %}AGG.SUM LR0 {{ full }}{% else %}ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% endif %}{% if not loop.last %} ; LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR1 1{% else %} {{ finish }}{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro add_planes(count,op='ADD',fmt=q,first=false,imm='CR1',base=cr.tmp,step='INC LR1 1',setup='',finish='') %}
 LD.MULT R0 LR1 {{ base }} {{ setup }} ;;
 {% for j in range(count) %}
 {{ vec(op,first and loop.first,imm,fmt,next='; LD.MULT R0 LR1 ' ~ base ~ ' ; ' ~ step if not loop.last else finish) }}
 {% endfor %}
{% endmacro %}
{% macro aq(reg,ds=full) -%}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }}
{%- endmacro %}
{% macro split(reg,count,ds=full,initial=true,setup='') %}
 {% if initial %}{{ aq(reg,ds) }} {{ setup }} ;;{% endif %}
 {% for p in range(1,count) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ; INC {{ reg }} 1 ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=2) %}{{ at('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{# AGG leaves the sum in lane zero. Broadcast each residual directly
   from R0 while multiplying by a plane of the reciprocal channel count. #}
{% macro average(finish='') %}
 {{ split('LR1',3,setup='; SET LR1 CR0') }}
 {% for stat in ['LR0','LR8','LR12'] %}
 {% set first_stat = loop.first %}
 {% set following = ['LR8','LR12',''][loop.index0] %}
 {% if first_stat %}LD.MULT.CYCLIC {{ stat }} {{ cr.stats }} LR0 ;;{% endif %}
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for next in ['LR8','LR12',''] %}
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first_stat and loop.first %}.FIRST{% endif %}{% if next %} ; LD.MULT R0 {{ next }} {{ cr.tmp }}{% elif following %} ; LD.MULT.CYCLIC {{ following }} {{ cr.stats }} LR0{% else %} {{ finish }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro added(reduce=false,first=false,finish='',setup='') %}
 LD.MULT R0 LR5 {{ cr.in0 }} {{ setup }} ;;
 {% set fetch = '; LD.MULT R0 LR10 ' ~ cr.addend %}
 {{ vec(first=not reduce or first,fmt=iq,reduce=reduce,next=fetch ~ ' ; SET LR10 LR5') }}
 {% for p in range(3) %}
 {{ vec(reduce=reduce,next=fetch ~ ' ; ADD LR10 LR10 LR13' if not loop.last else finish) }}
 {% endfor %}
{% endmacro %}
{% macro reset() %}
 SET LR5 LR2 ;;
 {{ at('LR9',32) }}
{% endmacro %}
{% macro store(ds) -%}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{%- endmacro %}
{% macro summed(first=false,setup='') %}
 {{ added(true,first,'; INC LR5 1 ; SET LR1 CR0',setup) }}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ;;
 SET LR8 CR1 ; SET LR12 CR1 ;;
 INC LR12 1 ; SET LR14 CR0 ; SET LR15 CR0 ;;
 INC LR14 128 ; INC LR15 128 ;;
 INC LR15 128 ; SET LR7 CR0 ;;
 INC LR7 12 ;;
row_loop:
 {{ summed(true,'; ADD LR6 LR2 ' ~ cr.K ~ ' ; SET LR5 LR2') }}
{% if s2_channels > 128 %}
sum_loop:
 {{ summed() }}
 BLT.S LR5 LR6 sum_loop ;;
{% endif %}
 {{ average('; SET LR1 CR0 ; SET LR5 LR2 ; SET LR9 CR0') }}
 {{ split('LR1',3,setup='; INC LR1 6 ; INC LR9 32 ; DEC LR6 1') }}

center_loop:
 {{ added(finish='; SET LR1 CR0') }}
 {% if aligned %}
 {{ add_planes(3,'SUB',setup='; INC LR1 6',finish='; ' ~ aq('LR9')) }}
 {{ split('LR9',2,initial=false) }}
 INC LR9 1 ; INC LR5 1 ; BLT.S LR5 LR6 center_loop ;;
 {% else %}
 {{ add_planes(3,'SUB',setup='; INC LR1 6') }}
 BEQ LR5 LR6 center_tail ;;
  {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ; BEQ LR0 CR0 center_loop ;;
center_tail:
   {{ split('LR9',2,tail) }}
 {% endif %}

 INC LR6 1 ;;
 {{ reset() }}{{ clear() }}
variance_loop:
 SET LR3 LR9 ;;
 {% for part in range(2) %}
 LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR0 {% if not loop.first %}; INC LR3 1{% endif %} ;;
 {{ dot(2,reduce=true,setup='; SET LR1 LR9',finish='; INC LR9 2 ; INC LR5 1 ; SET LR1 CR0' if loop.last else '') }}
 {% endfor %}
 BLT.S LR5 LR6 variance_loop ;;
 {{ average('; SET LR1 CR0') }}
 LD.MULT R0 LR1 {{ cr.stats }} ; INC LR1 3 ;;
 {{ vec(next='; ACTIVATE.QUANTIZE rsqrt ' ~ full ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR7') }}
 {{ save(9,2) }}
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR14 ;;
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ mul(first=true,slot='LR14') }}
 {{ save(14) }}
 {# Newton correction: delta = r * (1 - variance * r^2) / 2.
    Quantize the small correction on its own, not the refined r. #}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ; DEC LR1 1 ;;
 {{ at('LR1',4) }}
 LD.MULT R0 LR1 {{ cr.stats }} ;;
 {{ vec(first=true,next='; LD.MULT R0 LR1 ' ~ cr.tmp ~ ' ; INC LR1 5') }}
 {% for p in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB {% if loop.first %}; LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% endfor %}
 {{ save(13,1) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ;;
 MULT.RC.VE LR14 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul(first=true,slot='LR15') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; SET LR3 CR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ; INC LR3 20 ;;

 SET LR5 LR2 ; SET LR9 CR0 ; SET LR11 CR0 ;;
 INC LR9 32 ; DEC LR6 1 ;;
output_loop:
 LD.MULT R0 LR11 {{ cr.gamma }} ; SET LR10 LR11 ;;
 {% for part in range(3) %}
 {{ mul(first=loop.first,slot='LR14') }}
 {{ mul(slot='LR15',next='; LD.MULT R0 LR10 ' ~ cr.gamma ~ ' ; ADD LR10 LR10 ' ~ cr.K if not loop.last else '') }}
 {% endfor %}
  {{ save(20,2) }}
  {% for part in range(2) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; SET LR1 LR3 {% if not loop.first %}; INC LR9 1{% endif %} ;;
  {{ dot(2,first=loop.first,finish='; SET LR1 LR11 ; INC LR9 1' if loop.last else '') }}
 {% endfor %}
 {% if aligned %}
 {{ add_planes(3,base=cr.beta,step='ADD LR1 LR1 ' ~ cr.K,finish='; ' ~ store(full)) }}
 INC LR5 1 ; INC LR11 1 ; BLT.S LR5 LR6 output_loop ;;
 {% else %}
 {{ add_planes(3,base=cr.beta,step='ADD LR1 LR1 ' ~ cr.K) }}
 BNE LR5 LR6 output_full ;;
 {{ store(tail) }} ;;
 {% endif %}
 ADD LR2 LR6 CR1 ;;
 BLT.S LR2 LR13 row_loop ;;
 HALT ;;
{% if not aligned %}
output_full:
 {{ store(full) }} ;;
 INC LR5 1 ; INC LR11 1 ; BEQ LR0 CR0 output_loop ;;
{% endif %}
