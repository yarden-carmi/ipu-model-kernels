{% set q = cr.qf_in0 ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {{ adj(reg,n) }}
{% endmacro %}
{% macro adj(reg,d) %}
 {% for k in range((d|abs) // 255) %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} 255 ;;{% endfor %}
 {% if (d|abs) % 255 %}{{ 'INC' if d > 0 else 'DEC' }} {{ reg }} {{ (d|abs) % 255 }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds='CR15.L',tail='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',tail='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}

{# Packed storage lays out the strided view as contiguous channel planes.
   Take eight logical rows at a time from those planes. #}
{{ at('LR10',40 + 2 * rows) }}{{ at('LR11',rows // 8) }}
{{ at('LR15',120) }}
{% if rows % 128 %}{{ at('LR6',64) }}{% endif %}
SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
pack_tile:
 SET LR4 LR12 ; SET LR8 CR0 ;
 {% if rows % 128 %}BLT.S LR13 LR6 pack_low ;{% endif %} ;;
{% macro pack(half) %}
pack_{{ half }}:
 INC LR8 {{ channels // 16 }} ;;
pack_block_{{ half }}:
 SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; DEC LR8 1 ;;
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; ADDB LRD0 LR13 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% for i in range(16) %}
 {% if rows % 128 and i %}ADDBI LRD0 {{ (64 if i % 2 else -64) * (-1 if half == 'high' else 1) }} ; {% endif %}
 {% if i %}ADDBI LRD2 8 ; {% endif %}
 {% set stride = rows // 128 + (1 if rows % 128 and i % 2 == (0 if half == 'high' else 1) else 0) %}
 {% if stride %}INC LR4 {{ stride }} ; {% endif %}
 {% if not loop.last and stride %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;
 {% if loop.last %}ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ;{% endif %} ;;
 {% endfor %}
 INC LR10 1 ; BNE LR8 CR0 pack_block_{{ half }} ;;
 {% if half == 'high' %}B pack_tile_finish ;;{% endif %}
{% endmacro %}
{% if rows % 128 %}{{ pack('high') }}{% endif %}
{{ pack('low') }}
pack_tile_finish:
 INC LR13 8 ; DEC LR11 1 ; BLT.S LR13 LR15 pack_tile_next ;;
 SET LR13 CR0 ; INC LR12 1 ;;
pack_tile_next:
 BNE LR11 CR0 pack_tile ;;

 {# Four adjacent view rows land in four output slabs. Unroll that
    group to avoid checking the slab wrap after every row. #}
 {{ at('LR4',40 + 2 * rows) }}{{ at('LR11',rows) }}
 {{ at('LR9',40) }}{{ at('LR13',rows // 2) }}
 SET LR5 CR0 ; SET LR12 CR0 ;;
 SET LR6 {{ cr.c128 }} ; SET LR7 {{ cr.cC }} ;;
 {% for _ in range(3) %}ADD LR6 LR6 LR6 ; ADD LR7 LR7 LR7 ;;{% endfor %}
 unpack_row:
 {% macro unpack_one(i) %}
 SET LR10 LR4 ; SET LR0 LR6 ; SET LR1 LR7 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for h in range(2) %}
 ADDB LRD0 LR5 ; SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ;;
 {% for j in range(8 if h == 0 else channels // 16 - 8) %}
 {% if j %}ADDBI LRD0 -64 ; ADDBI LRD2 8 ; {% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD0 64 ; ADDBI LRD2 8 ;
 {% if not loop.last or h == 0 %}INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;{% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;
  {% if loop.last %}ACTIVATE.QUANTIZE identity {{ 'CR15.L' if h == 0 else cr.dsl ~ '.L' }} {{ q }} {{ cr.tmp }} {{ 'LR9' if h == 0 else 'LR15' }} ;{% endif %} ;;
 {% endfor %}
  {% if h == 0 %}ADD LR15 LR9 CR1 ; SET LR0 LR6 ; SET LR1 LR7 ;;{% endif %}
 {% endfor %}
 {% if i < 3 %}ADD LR9 LR9 LR13 ; {% endif %}INC LR5 1 ;;
 {% endmacro %}
 SET LR8 LR9 ;;
 {% for i in range(4) %}{{ unpack_one(i) }}{% endfor %}
 ADD LR9 LR8 CR1 ; DEC LR11 4 ; SET LR15 CR0 ;;
 INC LR9 1 ; INC.MODP2 LR15 LR11 3 ;;
 BNE LR15 CR0 unpack_continue ;;
 SET LR5 CR0 ; INC LR4 {{ channels // 16 }} ;;
 unpack_continue:
 BNE LR11 CR0 unpack_row ;;

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR2 1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
   INC LR8 32 ; SET LR12 CR0 ;;
   INC LR12 19 ;;
  {{ at('LR6',27) }}
  {{ at('LR7',9) }}
 {{ at('LR13',rows) }}
row_loop:
 {# Normalize while summing, rather than encoding and reloading the sum. #}
  SET LR1 CR0 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR0 ; SET LR5 LR14 ;;
  DEC LR13 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
   {% set slots = ['LR0','LR3','LR4'] %}
  {% set halves = ['CR15.L',cr.dsl ~ '.L'] %}
  {% for slot in slots %}
  {% set s = loop.index0 %}
  {% for i in range(2) %}
  {% set ds = halves[(s+i)%2] %}
    {% if i == 0 %}{{ 'DEC' if s % 2 else 'INC' }} LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ; {% elif s < 2 %}INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} {{ slots[s+1] }} ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if s == 0 and i == 0 %}.FIRST{% endif %} LR0 {{ ds }} {% if s == 2 and i == 1 %}; SET LR1 LR6 ; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
 {% endfor %}
  {# Keep the mean in lane zero and broadcast each piece at subtraction. #}
  SET LR9 LR8 ; SET LR5 LR14 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {{ scalar('SUB',tail='; INC LR1 1 ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1 ; LD.MULT R0 LR5 ' ~ cr.tmp) }}
  {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
  SET LR1 LR6 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {% for n in range(2) %}
  MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
  {% endfor %}
  LD.MULT R0 LR9 {{ cr.tmp }} ;;
  {{ scalar('SUB',ds=ds,tail='; INC LR9 2 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR9' ~ (' ; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.tmp if loop.first else ' ; SET LR5 LR8 ; LD.MULT.CYCLIC LR5 ' ~ cr.tmp ~ ' LR0')) }}
  {% if loop.first %}DEC LR9 1 ; SET LR1 LR6 ;;{% endif %}
 {% endfor %}

   SET LR9 LR8 ;;
  {% for h in range(2) %}
  {# Pipeline the two pieces; only the cross term needs Ra. #}
  INC LR9 2 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;
  MULT.RC.VS LR0 0 LR0 CR15.L {{ q }} ; AGG.SUM{% if h == 0 %}.FIRST{% endif %} LR0 CR15.L ;;
  LD.MULT R0 LR9 {{ cr.tmp }} ; MULT.RC.VS LR3 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
  {% for cross in range(2) %}
   {% if loop.last and h == 0 %}DEC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; {% elif loop.last %}LD.MULT R0 LR0 {{ cr.epsilon }} ; SET LR1 CR0 ; {% endif %}
  MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
  {% endfor %}
 {% endfor %}
 {# Work in sum-of-squares units: epsilon and gamma compensate in fold(). #}
  {# Refine in lane zero: with v = sum of squares plus epsilon and r
     the quantized rsqrt, form r * (2 + (1 - v*r*r)). #}
  {% set one = cr.ds1 ~ '.L' %}
  {{ scalar(ds=one,tail='; INC LR1 8 ; ACTIVATE.QUANTIZE rsqrt ' ~ one ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
  SET LR10 LR1 ; INC LR1 1 ; LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
  INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR3 ; MULT.RC.VS LR0 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
  SET LR10 CR1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {{ scalar('SUB',ds=one,tail='; INC LR1 1 ; ACTIVATE.QUANTIZE identity ' ~ one ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1 ; LD.MULT R1 LR10 ' ~ cr.epsilon) }}
  MULT.VE LR3 CR1 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ;;
  MULT.RC.VV LR3 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ; LD.MULT R1 LR1 {{ cr.tmp }} ;;
  MULT.RC.VV LR3 R1 0 LR0 {{ one }} {{ q }} ; ACC.SUB ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ; MULT.RC.VE LR0 CR1 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ;;
  MULT.RC.VE LR0 CR1 0 LR0 {{ one }} {{ q }} ; ACC.ADD ;;
  MULT.RC.VV LR0 R0 0 LR0 {{ one }} {{ q }} ; ACC.ADD ; SET LR1 LR12 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {{ scalar('SUB',ds=one,tail='; INC LR1 1 ; ACTIVATE.QUANTIZE identity ' ~ one ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}

 SET LR15 LR2 ; SET LR5 LR8 ; SET LR11 LR12 ;;
 {% for h in range(2) %}
 SET LR10 {{ 'CR0' if h == 0 else 'CR1' }} ; SET LR1 LR11 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 INC LR1 1 ; LD.MULT R1 LR1 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
  {% for i in range(2) %}
   MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
   MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ q }} ; ACC.ADD ; {% if not loop.last %}INC LR10 2 ; LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0{% else %}SET LR1 LR7 ; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
 {# Encode the gain while replacing the inverse slots with centered input. #}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR3'] %}
 {% if loop.first %}
 {{ scalar('SUB',tail='; INC LR1 1 ; LD.MULT.CYCLIC LR5 ' ~ cr.tmp ~ ' ' ~ slot ~ ' ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
 INC LR5 2 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% else %}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} {{ slot }} ;;
 {% endif %}
 {% endfor %}
 SET LR1 LR7 ; INC LR5 2 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(2) %}
  {{ mul(first=loop.first) }}
  {{ mul(slot='LR3',tail='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp if not loop.last else '; SET LR10 ' ~ ('CR0' if h == 0 else 'CR1') ~ ' ; LD.MULT R0 LR10 ' ~ cr.beta) }}
 {% endfor %}
  {% for i in range(2) %}
 {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta if not loop.last else '; INC LR15 1 ; DEC LR5 3 ; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' CR15.L ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR15') }}
 {% endfor %}
 {% endfor %}
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
