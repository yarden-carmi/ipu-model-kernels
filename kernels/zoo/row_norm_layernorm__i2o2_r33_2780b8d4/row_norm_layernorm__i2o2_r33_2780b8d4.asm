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
 {% if rows <= 256 %}
 {# Eight stored channel vectors pack without padding, so the backing
    storage is dense. The view then gives eight adjacent tokens per load. #}
 {{ at('LR10',39 + 2 * rows) }}{{ at('LR11',rows // 8) }}
 SET LR12 CR0 ; SET LR13 CR0 ; SET LR0 {{ cr.c128 }} ;;
 SET LR1 {{ cr.cC }} ; SET LR14 CR0 ;;
 pack_dense_tile:
 SET LR4 LR12 ; SET LR8 CR0 ;;
 INC LR8 {{ channels // 16 }} ;;
 {% if rows % 128 %}
 {{ at('LR7',rows // 128) }}{{ at('LR15',rows // 128 + 1) }}
 SET LR6 LR13 ;;
 INC.MODP2 LR6 CR0 6 ;;
 BLT.S LR6 LR13 pack_dense_high ;;
 INC LR6 64 ; B pack_dense_block ;;
 pack_dense_high:
 INC LR7 1 ; DEC LR15 1 ;;
 {% else %}
 {{ at('LR7',rows // 128) }}
 {% endif %}
 pack_dense_block:
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% for i in range(16) %}
 {% set stride = 'LR15' if rows % 128 and i % 2 else 'LR7' %}
 {% set ra = 'LR6' if rows % 128 and i % 2 else 'LR13' %}
 {% if i %}ADDBI LRD2 8 ; {% endif %}
 ADD LR4 LR4 {{ stride }} ; {% if not loop.last %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
 {% if loop.first %}INC LR10 1 ; {% endif %}
 MULT.VE {{ ra }} CR1 0 LR14 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;
 {% if loop.last %}ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ; DEC LR8 1 ; BLT.S CR1 LR8 pack_dense_block ;{% endif %} ;;
 {% endfor %}
 INC LR13 8 ; DEC LR11 1 ;;
 INC.MODP2 LR13 CR0 7 ;;
 BNE LR13 CR0 pack_dense_next ;;
 INC LR12 1 ;;
 pack_dense_next:
 BNE LR11 CR0 pack_dense_tile ;;
 {% else %}
{% set eu = namespace(a=rows, b=channels) %}
{% for _ in range(24) %}{% if eu.b %}{% set t = eu.b %}{% set eu.b = eu.a % eu.b %}{% set eu.a = t %}{% endif %}{% endfor %}
{% set M = eu.a %}
 {% if rows % 8 == 0 and channels % 16 == 0 %}
 {# Transpose an 8-row tile through interleaved blocks of 16 channels. #}
  {% set band = M if 128 % M == 0 and M % 8 == 0 else 16 %}
  {% set fast = channels % band == 0 and rows % band == 0 and rows // channels < 126 and ((channels // band <= 9 and (channels == 192 or channels == 144)) or (channels == 240 and rows < channels and channels // band <= 15)) %}
  {% set direct_store = fast and channels // band <= 9 %}
  {{ at('LR10',40 + 2 * rows - (1 if direct_store else 0)) }}{{ at('LR11',rows // 8) }}
  {{ at('LR14',channels) }}{{ at('LR15',128) }}
  SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
  pack_tile:
  {% if fast %}
 {# Each channel step rotates the source band. Pipeline a block with
    fixed row advances and lane shifts, then jump to its successor. #}
 {% set phases = channels // band %}
 {% set rotation = (rows % channels) // band %}
  {# For long phase cycles, share each half-block body across the tile. #}
  {% set chunk = 8 if phases > 9 else 16 %}
 SET LR4 LR12 ; SET LR8 CR0 ; SET LR9 CR0 ;;
 INC LR8 {{ channels // 16 }} ; INC.MODP2 LR9 LR13 {{ {8:3,16:4,32:5,64:6,128:7}[band] }} ; SET LR6 CR0 ;;
 {% if chunk < 16 %}
 SET LR5 CR0 ; SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ;;
 INC LR5 {{ 16 // chunk }} ;;
 {% endif %}
 {% for p in range(phases-1) %}
 {% if p*band == 128 %}INC LR4 1 ;;{% endif %}
 INC LR6 {{ band }} ;;
 BLT.S LR13 LR6 pack_phase{{ p }} ;;
 {% endfor %}
 {% if (phases-1)*band == 128 %}INC LR4 1 ; {% endif %}B pack_phase{{ phases-1 }} ;;
 {% macro pack_phase(p) %}
 pack_phase{{ p }}:
 {% if chunk == 16 %}
 SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; DEC LR8 1 ;;
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; ADDB LRD0 LR9 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% else %}
 SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; DEC LR5 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 ADDB LRD0 LR9 ;;
 {% endif %}
 {% for i in range(chunk) %}
 {% set phase = ((p+i*rotation) % phases)*band %}
 {% set prev = ((p+(i-1)*rotation) % phases)*band %}
 {% set next = (phase + rows) % channels %}
 {% set advance = 2*((phase+rows)//channels) + next//128 - phase//128 %}
 {% set shift = phase%128 - (prev%128 if i else 0) %}
 {% if shift %}ADDBI LRD0 {{ shift }} ; {% endif %}
 {% if i %}ADDBI LRD2 8 ; {% endif %}
  {% if advance %}INC LR4 {{ advance }} ; {% endif %}
  {% if direct_store and loop.first %}INC LR10 1 ; {% endif %}
  {% if not loop.last %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
  MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;
  {% if direct_store and loop.last %}ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ; BNE LR8 CR0 pack_phase{{ (p+chunk*rotation) % phases }} ;{% endif %} ;;
 {% endfor %}
 {% set successor = (p+chunk*rotation) % phases %}
 {% if chunk < 16 %}
 ADDBI LRD2 8 ; BNE LR5 CR0 pack_phase{{ successor }} ;;
 DEC LR8 1 ; INC LR5 {{ 16 // chunk }} ;;
 {% endif %}
  {% if not direct_store %}
  ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ;;
  INC LR10 1 ; {% if chunk < 16 %}SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; {% endif %}BNE LR8 CR0 pack_phase{{ successor }} ;;
  {% endif %}
 B pack_tile_finish ;;
 {% endmacro %}
 {% for p in range(phases) %}{{ pack_phase(p) }}{% endfor %}
 pack_tile_finish:
 {% else %}
 SET LR5 LR12 ; SET LR6 LR13 ; SET LR8 CR0 ;;
 INC LR8 {{ channels // 16 }} ;;
 pack_block:
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ;;
 {% macro scatter_channel(i) %}
  SET LR4 LR5 ; SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; BLT.S LR6 LR15 pack_low{{ i }} ;;
  INC LR4 1 ;;
 pack_low{{ i }}:
  {% if i %}ADDBI LRD2 8 ; {% endif %}INC.MODP2 LR7 LR6 7 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
  ADDB LRD0 LR7 ; SET LR7 CR0 ; {% if rows % channels %}INC LR6 {{ rows % channels }} ; {% endif %}
  MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
  {% if rows % channels %}BLT.S LR6 LR14 pack_nowrap{{ i }} ;;
  SUB LR6 LR6 LR14 ; INC LR5 2 ;;
 pack_nowrap{{ i }}:
  {% endif %}
  {% if rows // channels %}INC LR5 {{ 2 * (rows // channels) }} ;;{% endif %}
 {% endmacro %}
 {% for i in range(16) %}{{ scatter_channel(i) }}{% endfor %}
 DEC LR8 1 ; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ;;
 INC LR10 1 ; BNE LR8 CR0 pack_block ;;
 {% endif %}
 INC LR13 8 ; DEC LR11 1 ;;
 BLT.S LR13 LR14 pack_tile_next ;;
 SUB LR13 LR13 LR14 ; INC LR12 2 ;;
 pack_tile_next:
 BNE LR11 CR0 pack_tile ;;

 {% endif %}
 {% endif %}
   {{ at('LR4',40 + 2 * rows) }}{{ at('LR13',40 + 2 * rows + (rows // 8 - 1) * (channels // 16)) }}
  {{ at('LR14',7) }}
  {{ at('LR9',40) }}
  SET LR12 CR0 ;;
 SET LR6 {{ cr.c128 }} ; SET LR7 {{ cr.cC }} ;;
 {% for _ in range(3) %}ADD LR6 LR6 LR6 ; ADD LR7 LR7 LR7 ;;{% endfor %}
  unpack_tile:
  SET LR5 CR0 ;;
  unpack_row:
  SET LR10 LR4 ; SET LR0 LR6 ; SET LR1 LR7 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for h in range(2) %}
 {% for j in range(8 if h == 0 else channels // 16 - 8) %}
 {% if j %}ADDBI LRD0 -64 ; ADDBI LRD2 8 ; {% else %}ADDB LRD0 LR5 ; SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; {% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD0 64 ; ADDBI LRD2 8 ;
 {% if not loop.last or h == 0 %}INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;{% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;
  {% if loop.last %}ACTIVATE.QUANTIZE identity {{ 'CR15.L' if h == 0 else cr.dsl ~ '.L' }} {{ q }} {{ cr.tmp }} LR9 ;{% endif %} ;;
 {% endfor %}
  {% if h == 0 %}INC LR9 1 ; SET LR0 LR6 ; SET LR1 LR7 ;;{% endif %}
 {% endfor %}
  INC LR9 1 ; INC LR5 1 ; BLT.S LR5 LR14 unpack_row ;;
   INC LR4 {{ channels // 16 }} ; BLT.S LR4 LR13 unpack_tile ;;
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR2 CR1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
   ADD LR12 LR4 LR3 ; INC LR8 32 ;;
  {{ at('LR6',27) }}
  {{ at('LR7',9) }}
  {{ at('LR13',rows) }}
  {{ at('LR11',13) }}
 SET LR15 CR0 ; SET LR1 CR0 ;;
 DEC LR15 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR0 ;;
row_loop:
 {# Normalize while summing, rather than encoding and reloading the sum. #}
   SET LR1 CR0 ; SET LR5 LR14 ; DEC LR13 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
   {% set slots = ['LR0','LR3'] %}
  {% set halves = ['CR15.L',cr.dsl ~ '.L'] %}
  {% for slot in slots %}
  {% set s = loop.index0 %}
  {% for i in range(2) %}
  {% set ds = halves[(s+i)%2] %}
    {% if i == 0 %}{{ 'DEC' if s % 2 else 'INC' }} LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ; {% elif s + 1 < slots|length %}INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} {{ slots[s+1] }} ; {% else %}SET LR1 LR6 ; SET LR5 LR14 ; SET LR9 LR8 ; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR1 ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if s == 0 and i == 0 %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% endfor %}
 {% endfor %}
  {# Keep the mean in lane zero and broadcast each piece at subtraction. #}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {{ scalar('SUB',tail='; INC LR1 1 ; LD.MULT R0 LR5 ' ~ cr.tmp ~ ' ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
   {% if not loop.first %}DEC LR9 1 ; {% endif %}SET LR1 LR6 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {% for n in range(2) %}
  MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
  {% endfor %}
  {# Prefetch the next half, or seed the variance pass on the last half. #}
  LD.MULT R0 LR9 {{ cr.tmp }} ;;
  {{ scalar('SUB',ds=ds,tail='; INC LR9 2 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR9' ~ (' ; INC LR5 1 ; LD.MULT R0 LR5 ' ~ cr.tmp if loop.first else ' ; LD.MULT.CYCLIC LR8 ' ~ cr.tmp ~ ' LR0')) }}
 {% endfor %}

  {% for h in range(2) %}
  {# Pipeline the two pieces; only the cross term needs Ra. #}
   {% if h == 0 %}DEC LR9 1{% else %}INC LR9 2{% endif %} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;
  MULT.RC.VS LR0 0 LR0 CR15.L {{ q }} ; AGG.SUM{% if h == 0 %}.FIRST{% endif %} LR0 CR15.L ;;
  LD.MULT R0 LR9 {{ cr.tmp }} ; MULT.RC.VS LR3 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
  {% for cross in range(2) %}
   {% if loop.last and h == 0 %}DEC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; {% elif loop.last %}LD.MULT R0 LR0 {{ cr.epsilon }} ; SET LR1 CR0 ; {% endif %}
  MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
  {% endfor %}
 {% endfor %}
 {# Work in sum-of-squares units: epsilon and gamma compensate in fold(). #}
 {% set one = cr.ds1 ~ '.L' %}
  {# Refine the inverse in lane zero; fold the factor of 1/2 into gamma. #}
  {{ scalar(ds=one,tail='; INC LR1 8 ; ACTIVATE.QUANTIZE rsqrt ' ~ one ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
   SET LR10 LR1 ; INC LR1 1 ; LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
   INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR3 ; MULT.RC.VS LR0 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {{ scalar('SUB',ds=one,tail='; INC LR1 1 ; ACTIVATE.QUANTIZE identity ' ~ one ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1 ; LD.MULT R1 LR2 ' ~ cr.epsilon) }}
   MULT.VE LR3 CR1 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ;;
  MULT.RC.VV LR3 R0 0 LR0 {{ one }} {{ q }} ; ACC.SUB ; LD.MULT R1 LR1 {{ cr.tmp }} ;;
  MULT.RC.VV LR3 R1 0 LR0 {{ one }} {{ q }} ; ACC.SUB ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
   LD.MULT R0 LR1 {{ cr.tmp }} ; MULT.RC.VE LR0 CR1 0 LR0 {{ one }} {{ q }} ; ACC.ADD.FIRST ;;
  MULT.RC.VE LR0 CR1 0 LR0 {{ one }} {{ q }} ; ACC.ADD ;;
  MULT.RC.VV LR0 R0 0 LR0 {{ one }} {{ q }} ; ACC.ADD ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ one }} {{ q }} {{ cr.tmp }} LR1 ;;
  LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {{ scalar('SUB',ds=one,tail='; INC LR1 1 ; SET LR5 LR8 ; SET LR10 CR0 ; LD.MULT.CYCLIC LR10 ' ~ cr.gamma ~ ' LR0 ; ACTIVATE.QUANTIZE identity ' ~ one ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
 {% for h in range(2) %}
  {% if h == 0 %}SET LR1 LR11 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
 {% for i in range(2) %}
   MULT.RC.VE LR0 LR0 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if i==0 %}.FIRST ; INC LR1 1 ; LD.MULT R1 LR1 {{ cr.tmp }}{% endif %} ;;
   MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ q }} ; ACC.ADD ; {% if not loop.last %}INC LR10 2 ; LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0{% else %}SET LR1 LR7 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR4 ; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
 {# Encode the gain while replacing the inverse slots with centered input. #}
 INC LR5 2 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
  {{ scalar('SUB',tail='; INC LR1 1 ; LD.MULT.CYCLIC LR5 ' ~ cr.tmp ~ ' LR12 ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
 {% for i in range(2) %}
   {{ mul(first=loop.first,slot='LR4') }}
   {{ mul(slot='LR12',tail='; LD.MULT R0 LR1 ' ~ cr.tmp if not loop.last else '; SET LR10 ' ~ ('CR0' if h == 0 else 'CR1') ~ ' ; LD.MULT R0 LR10 ' ~ cr.beta) }}
 {% endfor %}
  {% for i in range(2) %}
   {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta if not loop.last else '; INC LR15 1 ; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' CR15.L ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR15' ~ (' ; DEC LR5 1 ; SET LR10 CR1 ; LD.MULT.CYCLIC LR10 ' ~ cr.gamma ~ ' LR0' if h == 0 else ' ; INC LR14 2 ; SET LR1 CR0 ; LD.MULT.CYCLIC LR1 ' ~ cr.crow ~ ' LR0 ; BNE LR13 CR0 row_loop')) }}
 {% endfor %}
 {% if h == 0 %}SET LR1 LR11 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
 {% endfor %}
 HALT ;;
