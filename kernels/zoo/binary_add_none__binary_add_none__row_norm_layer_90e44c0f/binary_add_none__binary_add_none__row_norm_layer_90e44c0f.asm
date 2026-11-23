{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set aligned = s2_channels % 128 == 0 %}
{% set chunks = (s2_channels + 127) // 128 %}
{# Keep long or tail-bearing channel axes on the bounded-size runtime path. #}
{% set pipeline = aligned and chunks <= 8 %}
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
 {# Broadcast the lane-zero reduction from R0, using either the
    reciprocal channel-count planes or the unit plane for a raw sum. #}
{% macro average(finish='', raw=false) %}
 {% set parts = 2 if pipeline else 3 %}
 {{ split('LR1',parts,setup='; SET LR1 CR0') }}
 {% for stat in (['LR11'] if raw else ['LR0','LR8']) %}
 {% set first_stat = loop.first %}
 {% set following = 'LR8' if not raw and loop.first else '' %}
 {% if first_stat %}LD.MULT.CYCLIC {{ stat }} {{ cr.stats }} LR0 ;;{% endif %}
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for next in (['LR8',''] if parts == 2 else ['LR8','LR12','']) %}
 MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first_stat and loop.first %}.FIRST{% endif %}{% if next %} ; LD.MULT R0 {{ next }} {{ cr.tmp }}{% elif following %} ; LD.MULT.CYCLIC {{ following }} {{ cr.stats }} LR0{% else %} {{ finish }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro added(reduce=false,first=false,finish='',setup='') %}
 LD.MULT R0 LR5 {{ cr.in0 }} {{ setup }} ;;
 {% set fetch = '; LD.MULT R0 LR10 ' ~ cr.addend %}
 {{ vec(first=not reduce or first,fmt=iq,reduce=reduce,next=fetch ~ ' ; SET LR10 LR5') }}
 {% for p in range(2) %}
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
 INC LR7 12 ; SET LR4 CR0 ;;
 INC LR4 6 ;;
row_loop:
{% if pipeline %}
 {# One row ahead through the input and both addend planes. #}
 LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR5 LR2 ; ADD LR6 LR2 {{ cr.K }} ; SET LR10 LR2 ;;
 {% for j in range(chunks) %}
 {{ vec(first=loop.first,fmt=iq,reduce=true,next='; LD.MULT R0 LR10 ' ~ cr.addend ~ ' ; SET LR10 LR5') }}
 {{ vec(reduce=true,next='; LD.MULT R0 LR10 ' ~ cr.addend ~ ' ; ADD LR10 LR10 LR13') }}
 {{ vec(reduce=true,next='; LD.MULT R0 LR5 ' ~ cr.in0 ~ ' ; INC LR5 1' if not loop.last else '; SET LR1 CR0') }}
 {% endfor %}
 {{ average('; SET LR1 CR0 ; SET LR5 LR2 ; SET LR9 CR0') }}
  {{ aq('LR1') }} ; INC LR1 6 ; INC LR9 32 ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {{ vec('SUB',next='; INC LR1 1 ; ' ~ aq('LR1') ~ ' ; LD.MULT R0 LR5 ' ~ cr.in0) }}
 {# Center and split each chunk, prefetching the next input on the low store. #}
 {% for j in range(chunks) %}
 {{ vec(first=true,fmt=iq,next='; LD.MULT R0 LR10 ' ~ cr.addend ~ ' ; SET LR10 LR5' ~ (' ; INC LR9 1' if not loop.first else '')) }}
 {{ vec(next='; LD.MULT R0 LR10 ' ~ cr.addend ~ ' ; ADD LR10 LR10 LR13') }}
 {{ vec(next='; LD.MULT R0 LR1 ' ~ cr.tmp ~ ' ; SET LR1 LR4') }}
 {% for p in range(2) %}
 {{ vec('SUB',next='; LD.MULT R0 LR1 ' ~ cr.tmp ~ ' ; INC LR1 1' if not loop.last else '; ' ~ aq('LR9')) }}
 {% endfor %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ vec('SUB',next='; ' ~ aq('LR9') ~ ' ; INC LR9 1' ~ (' ; LD.MULT R0 LR5 ' ~ cr.in0 ~ ' ; INC LR5 1' if not loop.last else '')) }}
 {% endfor %}
   {# Accumulate the leading terms high² + 2*high*low. #}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; DEC LR9 {{ 2 * chunks - 1 }} ;;
 {% for j in range(chunks) %}
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ full }} ; LD.MULT R0 LR9 {{ cr.tmp }} ; INC LR9 1 ;;
  MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ;;
  MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} {% if not loop.last %}; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; INC LR9 1{% else %}; SET LR1 CR0 ; SET LR11 LR8{% endif %} ;;
 {% endfor %}
{% else %}
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
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; LD.MULT R0 LR9 {{ cr.tmp }} ; INC LR9 1 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR14 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ; INC LR9 1 ;;
 MULT.RC.VS LR14 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; SET LR1 CR0 ; BLT.S LR5 LR6 variance_loop ;;
 {% endif %}
 {% if pipeline %}INC LR11 2 ;;{% endif %}
  {{ average('; SET LR1 CR0 ; LD.MULT R0 LR12 ' ~ cr.stats,pipeline) }}
 {{ vec(next='; ACTIVATE.QUANTIZE rsqrt ' ~ full ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR7') }}
 {% if not pipeline %}
 {{ save(9,2) }}
 LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR14 ;;
 LD.MULT R0 LR7 {{ cr.tmp }} ;;
 {{ mul(first=true,slot='LR14') }}
 {{ save(14) }}
 {# Newton correction: delta = r * (1 - variance * r^2) / 2.
    Quantize the small correction on its own, not the refined r. #}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ; DEC LR1 1 ;;
 {{ at('LR1',3) }}
 LD.MULT R0 LR1 {{ cr.stats }} ;;
 {{ vec(first=true,next='; LD.MULT R0 LR1 ' ~ cr.tmp ~ ' ; INC LR1 6') }}
 {% for p in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB {% if loop.first %}; LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR1 1{% endif %} ;;
 {% endfor %}
 {{ save(13,1) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ;;
 MULT.RC.VE LR14 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul(first=true,slot='LR15') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; SET LR3 CR0 ; SET LR5 LR2 ; SET LR9 CR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ; INC LR3 20 ; INC LR9 32 ; SET LR11 CR0 ;;
 {% else %}
  {{ aq('LR1') }} ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR14 ;;
  LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; SET LR3 CR0 ; SET LR5 LR2 ; SET LR9 CR0 ;;
  MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; {{ aq('LR1') }} ; INC LR1 1 ;;
  MULT.RC.VE LR14 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; {{ aq('LR1') }} ; INC LR1 1 ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {{ mul(true,slot='LR14',next='; ' ~ aq('LR3') ~ ' ; INC LR3 14') }}
  LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR15 ;;
  MULT.RC.VE LR15 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; {{ aq('LR3') }} ; LD.MULT R0 LR11 {{ cr.stats }} ; INC LR3 1 ; DEC LR1 2 ;;
  {{ vec(first=true,imm=cr.half,next='; LD.MULT R0 LR1 ' ~ cr.tmp) }}
  MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR3 {{ cr.tmp }} ;;
  MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR1 1 ;;
  MULT.RC.VV LR15 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR0 ;;
  MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; {{ aq('LR1') }} ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ; INC LR3 5 ; INC LR9 32 ; SET LR11 CR0 ;;
  {{ mul(true,slot='LR14',next='; ' ~ aq('LR1') ~ ' ; LD.MULT R0 LR11 ' ~ cr.gamma) }}
  LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ;;
 {% endif %}

{% macro output_chunk(pipelined=false,first=false,last=false) %}
 {% if not pipelined %}
 LD.MULT R0 LR11 {{ cr.gamma }} ; SET LR10 LR11 ;;
 {% endif %}
 {% for part in range(2) %}
  {% set next = '; LD.MULT R0 LR10 ' ~ cr.gamma ~ ' ; ADD LR10 LR11 ' ~ cr.K if not loop.last else '; ' ~ aq('LR3') ~ ' ; SET LR1 LR3' %}
  {% set setup = '; INC LR5 1' if pipelined and loop.first and not first else '' %}
   {{ mul(first=loop.first,slot='LR14',next=setup ~ (next if pipelined and loop.last else '')) }}
   {% if not pipelined or not loop.last %}{{ mul(slot='LR15',next=next) }}{% endif %}
 {% endfor %}
 LD.MULT R0 LR3 {{ cr.tmp }} ; INC LR1 1 ;;
 {{ vec('SUB',next='; ' ~ aq('LR1') ~ ' ; LD.MULT.CYCLIC LR9 ' ~ cr.tmp ~ ' LR0') }}
 {# R0 still holds the high product; alternate the centered rows while
    keeping the high and low product planes live in R0 and R1. #}
 {{ mul(true,next='; LD.MULT R1 LR1 ' ~ cr.tmp ~ ' ; INC LR9 1') }}
 MULT.RC.VV LR0 R1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
  {% if pipelined %}
  {{ mul(next='; INC LR9 1 ; LD.MULT R0 LR1 ' ~ cr.beta ~ ' ; SET LR1 LR11') }}
  {% else %}
  {{ mul(next='; INC LR9 1') }}
  MULT.RC.VV LR0 R1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; LD.MULT R0 LR1 {{ cr.beta }} ; SET LR1 LR11 ;;
  {% endif %}
  {{ vec(next='; LD.MULT R0 LR1 ' ~ cr.beta ~ ' ; ADD LR1 LR1 ' ~ cr.K ~ (' ; SET LR2 LR6' if pipelined and last else '')) }}
  {% if aligned %}
     {{ vec(next='; ' ~ store(full) ~ (' ; LD.MULT R0 LR11 ' ~ cr.gamma ~ ' ; INC LR11 1' if pipelined and not last else ' ; BLT.S LR2 LR13 row_loop' if pipelined else '')) }}
 {% else %}
  {{ vec() }}
 BNE LR5 LR6 output_full ;;
  {{ store(tail) }} ;;
 {% endif %}
{% endmacro %}
{% if pipeline %}
 {# Subsequent gamma highs are fetched in the preceding output store. #}
 {% for j in range(chunks) %}
 {{ output_chunk(true,loop.first,loop.last) }}
 {% endfor %}
{% else %}
 DEC LR6 1 ;;
output_loop:
 {{ output_chunk() }}
 {% if aligned %}INC LR5 1 ; INC LR11 1 ; BLT.S LR5 LR6 output_loop ;;{% endif %}
 ADD LR2 LR6 CR1 ;;
{% endif %}
 {% if not pipeline %}BLT.S LR2 LR13 row_loop ;;{% endif %}
 HALT ;;
{% if not aligned %}
output_full:
 {{ store(full) }} ;;
 INC LR5 1 ; INC LR11 1 ; BEQ LR0 CR0 output_loop ;;
{% endif %}
