{% set q = cr.qf_in0 ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {{ adj(reg,n) }}
{% endmacro %}
{% macro adj(reg,d) %}
 {% for k in range((d|abs) // 255) %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} 255 ;;{% endfor %}
 {% if (d|abs) % 255 %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} {{ (d|abs) % 255 }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {% if n %}SET LR1 CR0 ;;{% endif %}
 {% if n %}INC LR1 {{ n }} ; {% endif %}
 {% if cy %}LD.MULT.CYCLIC {{ 'LR1' if n else 'LR0' }} {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 {{ 'LR1' if n else 'LR0' }} {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds='CR15.L',tail='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',tail='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds='CR15.L',setup='') %}
 {% for i in range(pieces) %}
 {% if loop.first %}{{ setup }}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;{% endif %}
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,tail='; INC ' ~ reg ~ ' 1 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' ' ~ reg) }}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {% if n %}SET LR1 CR0 ;;{% endif %}
 {{ encode('LR1',pieces,setup=('INC LR1 ' ~ n ~ ' ; ' if n else 'SET LR1 CR0 ; ')) }}
{% endmacro %}
{% macro broadcast_sum(next_load='') %}
 {{ save(0,2) }}
 SET LR1 CR0 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for j in range(2) %}
 {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ; {% else %}{{ next_load }}{% endif %}MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 SET LR1 CR0 ;;
 INC LR1 {{ b }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 {{ 'INC' if a > b+1 else 'DEC' }} LR1 {{ (a-b-1)|abs }} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 {{ mul(first=(i==0),slot='LR3') }}
 {{ mul(slot='LR4',tail='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp if i==0 else '') }}
 {% endfor %}
 {% if a == 11 %}INC LR1 10 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;{{ mul(slot='LR3') }}{% endif %}
 {{ save(dest) }}
{% endmacro %}

{# Channel planes of the view are contiguous in packed storage. #}
{{ at('LR10',40 + 2 * rows) }}{{ at('LR11',rows // 8) }}
SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
pack_tile:
 SET LR4 LR12 ; SET LR8 CR0 ;;
 INC LR8 {{ channels // 16 }} ;;
pack_block:
 SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; DEC LR8 1 ;;
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; ADDB LRD0 LR13 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% for i in range(16) %}
 {% if rows % 128 and i %}ADDBI LRD0 {{ 64 if i % 2 else -64 }} ; {% endif %}
 {% if i %}ADDBI LRD2 8 ; {% endif %}
 {% set stride = rows // 128 + (1 if rows % 128 and i % 2 else 0) %}
 {% if stride %}INC LR4 {{ stride }} ; {% endif %}
 {% if not loop.last and stride %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 {% endfor %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ;;
 INC LR10 1 ; BNE LR8 CR0 pack_block ;;
 INC LR13 8 ; DEC LR11 1 ;;
 BLT.S LR13 {{ cr.tile_lanes }} pack_next ;;
 SET LR13 CR0 ; INC LR12 1 ;;
pack_next:
 BNE LR11 CR0 pack_tile ;;

 {{ at('LR4',40 + 2 * rows) }}{{ at('LR11',rows) }}
 {{ at('LR9',40) }}{{ at('LR8',7) }}
 SET LR5 CR0 ; SET LR12 CR0 ;;
 SET LR6 {{ cr.c128 }} ; SET LR7 {{ cr.cC }} ;;
 {% for _ in range(3) %}ADD LR6 LR6 LR6 ; ADD LR7 LR7 LR7 ;;{% endfor %}
 unpack_row:
 SET LR10 LR4 ; SET LR0 LR6 ; SET LR1 LR7 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for h in range(2) %}
 ADDB LRD0 LR5 ; SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ;;
 {% for j in range(8 if h == 0 else channels // 16 - 8) %}
 {% if j %}ADDBI LRD0 -64 ; ADDBI LRD2 8 ; {% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD0 64 ; ADDBI LRD2 8 ;
 {% if not loop.last or h == 0 %}INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;{% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;
 {% if loop.last %}ACTIVATE.QUANTIZE identity {{ 'CR15.L' if h == 0 else cr.dsl ~ '.L' }} {{ q }} {{ cr.tmp }} LR9 ;{% endif %} ;;
 {% endfor %}
 {% if h == 0 %}INC LR9 1 ; SET LR0 LR6 ; SET LR1 LR7 ;;{% endif %}
 {% endfor %}
 INC LR9 1 ; INC LR5 1 ; DEC LR11 1 ; BLT.S LR5 LR8 unpack_continue ;;
 SET LR5 CR0 ; INC LR4 {{ channels // 16 }} ;;
 unpack_continue:
 BNE LR11 CR0 unpack_row ;;

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR2 1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
  ADD LR12 LR4 LR3 ; INC LR8 3 ;;
  {{ at('LR6',27) }}
  {{ at('LR7',9) }}
 {{ at('LR13',rows) }}
row_loop:
  {# Normalize while summing, rather than encoding and reloading the sum. #}
  {% for slot in ['LR0','LR3','LR4'] %}
  {% set first_slot = loop.first %}
  {% if loop.first %}SET LR1 CR0 ; {% else %}INC LR1 1 ; {% endif %}LD.MULT.CYCLIC LR1 {{ cr.crow }} {{ slot }} ; SET LR5 LR14 ;;
  {% if first_slot %}DEC LR13 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
  {% if loop.first %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if first_slot and loop.first %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% endfor %}
 {% endfor %}
  {# Keep the mean in lane zero and broadcast each piece at subtraction. #}
  {{ save(27,2) }}

 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
  {% if not loop.first %}INC LR5 1 ; DEC LR9 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
  SET LR1 LR6 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {% for n in range(2) %}
  MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
  {% endfor %}
  {% for n in range(1) %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,tail='; INC LR9 2 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR9') }}
 {% endfor %}
  {% endfor %}

 {{ scalar(first=true,imm='CR0',tail='; SET LR9 CR0') }}
 {% for h in range(2) %}
  {% for slot in ['LR0','LR3'] %}
 INC LR9 {{ (32 if h == 0 else 1) if loop.first else 2 }} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} {{ slot }}{% if loop.first %} ; SET LR10 CR0{% endif %} ;;
 {% endfor %}
 INC LR10 {{ 32 + h }} ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
  {% for slot in ['LR0','LR3'] %}
 {% set last_slot = loop.last %}
  {% for i in range(2) %}
  {% if not (last_slot and loop.last) %}{{ 'DEC LR10 2' if loop.last else 'INC LR10 2' }} ; LD.MULT R0 LR10 {{ cr.tmp }} ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
 {% endfor %}
 {% endfor %}
  {% if h == 0 %}DEC LR9 2 ;;{% endif %}
 {% endfor %}
 {# Work in sum-of-squares units: epsilon and gamma compensate in fold(). #}
 {{ broadcast_sum('LD.MULT R0 LR0 ' ~ cr.epsilon ~ ' ; ') }}
 {{ scalar(tail='; SET LR1 CR0') }}
 INC LR1 8 ; ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Refine the approximate inverse standard deviation and keep two pieces. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
  {# Accumulate twice the Newton correction directly; gamma carries the factor 1/2. #}
  {{ load(8,true) }}
  MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ; INC LR1 7 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
  MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
  MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
  {{ mul(op='SUB',tail='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp) }}
  {{ mul(op='SUB') }}
  {{ save(19,2) }}

 SET LR15 LR2 ; SET LR5 CR0 ; SET LR11 CR0 ;;
 INC LR5 32 ; INC LR11 19 ;;
 {% for h in range(2) %}
 SET LR10 {{ 'CR0' if h == 0 else 'CR1' }} ; SET LR1 LR11 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
  LD.MULT R0 LR10 {{ cr.gamma }} ;;
  {% for i in range(3) %}
  {% if loop.last %}
  {{ mul(tail='; SET LR1 LR7 ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
  {% else %}
  {{ mul(first=i==0) }}
  {{ mul(slot='LR3',tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.gamma) }}
  {% endif %}
 {% endfor %}
 {# Encode the gain while replacing the inverse slots with centered input. #}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in ['LR0'] %}
 {{ scalar('SUB',tail='; INC LR1 1 ; LD.MULT.CYCLIC LR5 ' ~ cr.tmp ~ ' ' ~ slot ~ ' ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
 INC LR5 2 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% endfor %}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR3 ;;
 INC LR5 2 ; SET LR1 LR7 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {% for i in range(2) %}
  {{ mul(first=loop.first) }}{{ mul(slot='LR3',tail='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp) }}
  {% endfor %}
  SET LR10 {{ 'CR0' if h == 0 else 'CR1' }} ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta if not loop.last else '; INC LR15 1 ; DEC LR5 3 ; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' CR15.L ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR15') }}
 {% endfor %}
 {% endfor %}
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
