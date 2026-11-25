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
 {{ save(0,3) }}
 SET LR1 CR0 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for j in range(3) %}
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

{# Gather the strided view in output row order by grouping fixed source lanes. #}
{% set eu = namespace(a=rows, b=channels) %}
{% for _ in range(24) %}{% if eu.b %}{% set t = eu.b %}{% set eu.b = eu.a % eu.b %}{% set eu.a = t %}{% endif %}{% endfor %}
{% set M = eu.a %}
{% set T = channels // M %}
{% set step = 2 * (rows // M) %}
{% set r = 127 % T %}
{% macro group(label,ja,jb,n,mlo,mhi,h) %}
 {% set start = T * mlo - 128 * h %}
 {% set piped = step <= 255 and T <= 127 %}
 {{ at('LR14',jb + (start if piped else 0)) }}{{ at('LR11',ja + (start if piped else 0)) }}
{{ label }}_group:
 SET LR10 LR7 ; SET LR6 LR8 ; SET LR3 CR0 ; BLT.S LR8 {{ cr.c128 }} {{ label }}_low ;;
 INC LR10 1 ; SUB LR6 LR8 {{ cr.c128 }} ;;
 {{ label }}_low:
 {% set offset = T * mhi - 128 * h %}
 {% set updates %}{% if rows % channels %}INC LR8 {{ rows % channels }} ; {% endif %}INC LR11 1 ; {% endset %}
 {% if piped %}
 {# Ascending source order starts directly at the first destination lane. #}
 ADDB LRD2 LR11 ; SET LR12 CR0 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
 {% if n > 1 %}INC LR10 {{ step }} ; INC LR12 {{ n - 2 }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ;;{% endif %}
 {% if n > 2 %}
 {{ label }}_pipe:
 INC LR10 {{ step }} ; ADDBI LRD2 {{ T }} ; DEC LR12 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ; MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; BLT.S CR1 LR12 {{ label }}_pipe ;;
 {% endif %}
 {% if n > 1 %}ADDBI LRD2 {{ T }} ; {% endif %}{{ updates }}MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 {% else %}
 ADDB LRD2 LR11 ; SET LR12 CR0 ;;
 {% for k in range((offset + 126) // 127) %}ADDBI LRD2 {{ [127,offset - 127 * k]|min }} ;;{% endfor %}
 {{ adj('LR12',n) }}
{{ label }}_elem:
 {% if step > 255 %}{{ adj('LR10',-step) }}{% endif %}
 {% if T > 128 %}ADDBI LRD2 -128 ;;{% endif %}
 {% if step <= 255 %}DEC LR10 {{ step }} ; {% endif %}ADDBI LRD2 -{{ T if T <= 128 else T - 128 }} ; DEC LR12 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
 MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; BNE LR12 CR0 {{ label }}_elem ;;
 {{ updates }};
 {% endif %}
 {% if 2 * (rows // channels) %}INC LR7 {{ 2 * (rows // channels) }} ; {% endif %}BLT.S LR8 {{ cr.cC }} {{ label }}_next ;;
 SUB LR8 LR8 {{ cr.cC }} ; INC LR7 2 ;;
{{ label }}_next:
 BNE LR11 LR14 {{ label }}_group ;;
{% endmacro %}

 {% if rows % 8 == 0 and channels % 16 == 0 %}
 {# Transpose an 8-row tile through interleaved blocks of 16 channels. #}
 {{ at('LR10',40 + 2 * rows) }}{{ at('LR11',rows // 8) }}
 {{ at('LR14',channels) }}{{ at('LR15',128) }}
 SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
 pack_tile:
 {% set band = M if 128 % M == 0 and M % 8 == 0 else 16 %}
 {% if channels % band == 0 and rows % band == 0 and rows // channels < 126 and ((channels // band <= 9 and (channels == 192 or channels == 144)) or (channels == 240 and rows < channels and channels // band <= 15)) %}
 {# Each channel step rotates the source band. Pipeline a block with
    fixed row advances and lane shifts, then jump to its successor. #}
 {% set phases = channels // band %}
 {% set rotation = (rows % channels) // band %}
 {# For long phase cycles, share each four-channel body across the tile. #}
 {% set chunk = 4 if phases > 9 else 16 %}
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
 {% if not loop.last %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 {% endfor %}
 {% set successor = (p+chunk*rotation) % phases %}
 {% if chunk < 16 %}
 ADDBI LRD2 8 ; BNE LR5 CR0 pack_phase{{ successor }} ;;
 DEC LR8 1 ; INC LR5 {{ 16 // chunk }} ;;
 {% endif %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ;;
 INC LR10 1 ; {% if chunk < 16 %}SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; {% endif %}BNE LR8 CR0 pack_phase{{ successor }} ;;
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

 {{ at('LR4',40 + 2 * rows) }}{{ at('LR11',rows) }}
 {{ at('LR9',40) }}{{ at('LR13',rows // 2) }}
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
 DEC LR9 1 ; INC LR5 1 ; DEC LR11 1 ;;
 ADD LR9 LR9 LR13 ; SET LR15 CR0 ;;
 INC.MODP2 LR15 LR11 2 ;;
 BNE LR15 CR0 unpack_next ;;
 {% for _ in range(4) %}SUB LR9 LR9 LR13 ;;{% endfor %}
 INC LR9 2 ;;
 unpack_next:
 SET LR15 CR0 ;;
 INC.MODP2 LR15 LR11 3 ;;
 BNE LR15 CR0 unpack_continue ;;
 SET LR5 CR0 ; INC LR4 {{ channels // 16 }} ;;
 unpack_continue:
 BNE LR11 CR0 unpack_row ;;
 {% else %}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 {{ at('LR1',rows) }}{{ at('LR9',40) }}{{ at('LR13',rows // 2) }}
gather:
 {% for h in range(2) %}
 SET LR7 LR4 ; SET LR8 LR5 ;;
 {% set ns = namespace(prev=0) %}
 {% for seg in range(2) %}
 {% set ja = 0 if seg == 0 else r + 1 %}
 {% set jb = r + 1 if seg == 0 else T %}
 {% set mid = 127 // T + (1 if seg == 0 else 0) %}
 {% set hi = mid if h == 0 else M %}
 {% set n = mid if h == 0 else M - mid %}
 {% if jb > ja and n > 0 %}
  {% set base = step * ((0 if h == 0 else mid) if step <= 255 and T <= 127 else hi) %}
  {{ adj('LR7',base - ns.prev) }}
  {% set ns.prev = base %}
  {{ group('g%d%d' % (h,seg),ja,jb,n,0 if h == 0 else mid,hi,h) }}
 {% endif %}
 {% endfor %}
 {% if h == 0 %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR9 ;;
 ADD LR15 LR9 CR1 ;;
 {% else %}
 ACTIVATE.QUANTIZE identity {{ cr.dsl }}.L {{ q }} {{ cr.tmp }} LR15 ;;
 {% endif %}
 {% endfor %}
 ADD LR9 LR9 LR13 ; INC LR5 1 ; DEC LR1 1 ;;
 BLT.S LR5 {{ cr.cC }} gather_no_wrap ;;
 SUB LR5 LR5 {{ cr.cC }} ; INC LR4 2 ;;
gather_no_wrap:
 SET LR15 CR0 ;;
 INC.MODP2 LR15 LR1 2 ;;
 BNE LR15 CR0 gather_next ;;
 {% for _ in range(4) %}SUB LR9 LR9 LR13 ;;{% endfor %}
 INC LR9 2 ;;
gather_next:
 BNE LR1 CR0 gather ;;
 {% endif %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR2 1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
  ADD LR12 LR4 LR3 ; INC LR8 3 ;;
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
  {% if i == 0 %}{{ 'DEC' if s % 2 else 'INC' }} LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ; {% elif s < 2 %}INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} {{ slots[s+1] }} ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if s == 0 and i == 0 %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% endfor %}
 {% endfor %}
  {# Keep the mean in lane zero and broadcast each piece at subtraction. #}
   {{ save(27,2) }}

 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
 {% if not loop.first %}INC LR5 1 ; INC LR9 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
  SET LR1 LR6 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {% for n in range(2) %}
  MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
  {% endfor %}
  {% for n in range(1) %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,tail='; INC LR9 2 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR9') }}
 {% endfor %}
  DEC LR9 2 ;;
 {% endfor %}

  {{ scalar(first=true,imm='CR0',tail='; SET LR9 CR0') }}
  INC LR9 32 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
  {% for h in range(2) %}
  {# Pipeline the two pieces; only the cross term needs Ra. #}
  INC LR9 2 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;
  MULT.RC.VS LR0 0 LR0 CR15.L {{ q }} ; AGG.SUM{% if h == 0 %}.FIRST{% endif %} LR0 CR15.L ;;
  LD.MULT R0 LR9 {{ cr.tmp }} ; MULT.RC.VS LR3 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
  {% for cross in range(2) %}
  {% if loop.last and h == 0 %}DEC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; {% endif %}
  MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
  {% endfor %}
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
  {{ mul(first=i==0) }}
  {{ mul(slot='LR3',tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.gamma if not loop.last else '; SET LR1 LR7 ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
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
 {% for i in range(3) %}
 {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta if not loop.last else '; INC LR15 1 ; DEC LR5 3 ; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' CR15.L ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR15') }}
 {% endfor %}
 {% endfor %}
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
