{% set cr = dict(in0=cr.in0, out0=cr.out0, qf_in0=cr.qf_in0, qf_out0=cr.qf_out0, gamma=cr.gamma, beta=cr.beta, crow=cr.scalars, tmp=cr.tmp, c128=cr.c128, cC=cr.cC, epsilon=cr.epsilon, ds1=cr.ds1, dsl=cr.dsl) %}
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
{% macro save(n,pieces=2,ds='CR15.L') %}
 {% if n %}SET LR1 CR0 ;;{% endif %}
 {{ encode('LR1',pieces,ds=ds,setup=('INC LR1 ' ~ n ~ ' ; ' if n else 'SET LR1 CR0 ; ')) }}
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

 {% if false %}
 {# The packed input is flat in storage order: channel planes are rows elements apart. #}
 {{ at('LR10',39 + 2 * rows) }}{{ at('LR11',rows // 8) }}
 SET LR12 CR0 ; SET LR9 CR0 ; SET LR7 CR0 ;; {{ at('LR6',128) }}
 flat_tile:
 SET LR4 LR12 ; SET LR8 CR0 ; SET LR0 {{ cr.c128 }} ;;
 SET LR1 {{ cr.cC }} ; INC LR8 {{ channels // 16 }} ;;
 ADDB LRD0 LR9 ;;
 {% if rows % 128 %}ADDBI LRD0 64 ;;
 {% endif %}
 flat_block:
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; INC LR10 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% for i in range(16) %}
 {% if i %}ADDBI LRD2 8 ; {% endif %}
 {% if rows % 128 %}ADDBI LRD0 {{ 64 if i % 2 else -64 }} ; {% endif %}
 {% set advance = rows // 128 + (i % 2 if rows % 128 else 0) %}
 {% if advance %}INC LR4 {{ advance }} ; {% endif %}
 {% if loop.first %}DEC LR8 1 ; {% endif %}
 {% if not loop.last and advance %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 {% if loop.last %}; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ; BNE LR8 CR0 flat_block{% endif %} ;;
 {% endfor %}
 INC LR9 8 ;;
 BNE LR9 LR6 flat_next ;; INC LR12 1 ; SET LR9 CR0 ;;
 flat_next:
 DEC LR11 1 ;;
 BNE LR11 CR0 flat_tile ;;
 {% elif rows % 8 == 0 and channels % 16 == 0 %}
 {# Transpose an 8-row tile through interleaved blocks of 16 channels. #}
 {{ at('LR10',39 + 2 * rows) }}{{ at('LR11',rows // 8) }}
 {{ at('LR14',channels) }}{{ at('LR15',128) }}
 SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
 pack_tile:
 {% set band = M if 128 % M == 0 and M % 8 == 0 else 16 %}
 {% if channels % band == 0 and rows % band == 0 and rows // channels < 126 and ((channels // band <= 9 and (channels == 192 or channels == 144)) or (channels == 240 and rows < channels and channels // band <= 15)) %}
 {# Each channel step rotates the source band. Pipeline a block with
    fixed row advances and lane shifts, then jump to its successor. #}
 {% set phases = channels // band %}
 {% set rotation = (rows % channels) // band %}
   {# Emit a complete packed row per phase to avoid half-block dispatch. #}
   {% set chunk = 16 %}
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
  {% set stream = channels == 144 and rotation == 1 %}
  {% if stream %}
  {# Carry both reshape indices across blocks. The 128-to-0 band
     transition has no lane shift, leaving a slot to bump the store pointer. #}
  SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; ADD LR8 LR8 LR10 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
  SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; ADDB LRD0 LR9 ;;
  ADDBI LRD2 120 ; ADDBI LRD0 {{ (((p-rotation) % phases)*band) % 128 }} ;;
  pack_stream{{ p }}:
  {% set done = namespace(bumped=false) %}
  {% for i in range(16) %}
  {% set phase = ((p+i*rotation) % phases)*band %}
  {% set prev = ((p+(i-1)*rotation) % phases)*band %}
  {% set next = (phase + rows) % channels %}
  {% set advance = 2*((phase+rows)//channels) + next//128 - phase//128 %}
  {% set shift = phase%128 - prev%128 %}
  {% if shift %}ADDBI LRD0 {{ shift }} ;{% elif not done.bumped %}INC LR10 1 ;{% set done.bumped = true %}{% endif %}
  ADDBI LRD2 {{ 8 if i else -120 }} ; INC LR4 {{ advance }} ; LD.MULT R0 LR4 {{ cr.in0 }} ;
  MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 {% if i == 14 %}; BEQ LR10 LR8 pack_last{{ p }}{% elif loop.last %}; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ; B pack_stream{{ (p+16*rotation) % phases }}{% endif %} ;;
  {% endfor %}
  pack_last{{ p }}:
  {% set last_shift = (((p+15*rotation) % phases)*band) % 128 - (((p+14*rotation) % phases)*band) % 128 %}
  {% if last_shift %}ADDBI LRD0 {{ last_shift }} ;{% endif %}
  ADDBI LRD2 8 ; MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ; B pack_tile_finish ;;
  {% elif chunk == 16 %}
 SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; INC LR10 1 ;;
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; ADDB LRD0 LR9 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {% else %}
 SET LR0 {{ cr.c128 }} ; SET LR1 {{ cr.cC }} ; DEC LR5 1 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
 ADDB LRD0 LR9 ;;
 {% endif %}
  {% if not stream %}{% for i in range(chunk) %}
 {% set phase = ((p+i*rotation) % phases)*band %}
 {% set prev = ((p+(i-1)*rotation) % phases)*band %}
 {% set next = (phase + rows) % channels %}
 {% set advance = 2*((phase+rows)//channels) + next//128 - phase//128 %}
 {% set shift = phase%128 - (prev%128 if i else 0) %}
 {% if shift %}ADDBI LRD0 {{ shift }} ; {% endif %}
 {% if i %}ADDBI LRD2 8 ; {% endif %}
 {% if advance %}INC LR4 {{ advance }} ; {% endif %}
 {% if loop.first and chunk == 16 %}DEC LR8 1 ; {% endif %}
 {% if not loop.last %}LD.MULT R0 LR4 {{ cr.in0 }} ; {% endif %}
 MULT.VE LR7 CR1 0 LR7 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 {% if loop.last and chunk == 16 %}; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ; BNE LR8 CR0 pack_phase{{ (p+chunk*rotation) % phases }}{% endif %} ;;
 {% endfor %}
 {% set successor = (p+chunk*rotation) % phases %}
 {% if chunk < 16 %}
 ADDBI LRD2 8 ; BNE LR5 CR0 pack_phase{{ successor }} ;;
 DEC LR8 1 ; INC LR5 {{ 16 // chunk }} ;;
 {% endif %}
 {% if chunk < 16 %}ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR10 ;;{% endif %}
 {% if chunk < 16 %}INC LR10 1 ; SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; BNE LR8 CR0 pack_phase{{ successor }} ;;{% endif %}
  B pack_tile_finish ;;
  {% endif %}
 {% endmacro %}
 {% for p in range(phases) %}{{ pack_phase(p) }}{% endfor %}
 pack_tile_finish:
 {% else %}
 SET LR5 LR12 ; SET LR6 LR13 ; SET LR8 CR0 ;;
 INC LR8 {{ channels // 16 }} ;;
 pack_block:
 SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ; INC LR10 1 ;;
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
 BNE LR8 CR0 pack_block ;;
 {% endif %}
 INC LR13 8 ; DEC LR11 1 ;;
 BLT.S LR13 LR14 pack_tile_next ;;
 SUB LR13 LR13 LR14 ; INC LR12 2 ;;
 pack_tile_next:
 BNE LR11 CR0 pack_tile ;;

 {% endif %}
 {% if true %}
 {{ at('LR4',40 + 2 * rows) }}{{ at('LR11',rows // 8) }}
  {{ at('LR9',40) }}{{ at('LR13',rows // 2 - (0 if channels == 144 else 1)) }}
 {{ at('LR15',2) }}
 SET LR5 CR0 ; SET LR12 CR0 ;;
 SET LR6 {{ cr.c128 }} ; SET LR7 {{ cr.cC }} ;;
 {% for _ in range(3) %}ADD LR6 LR6 LR6 ; ADD LR7 LR7 LR7 ;;{% endfor %}
 unpack_tile:
 SET LR0 LR6 ; SET LR1 LR7 ; ADD LR14 LR9 LR15 ;;
  {% macro unpack(i) %}
  {# For the one-block tail, preload the next row on the last tail multiply. #}
  {% if channels != 144 or i == 0 %}SET LR10 LR4 ; {% if i == 4 %}SET LR9 LR14 ;{% elif i %}ADD LR9 LR9 LR13 ;{% endif %} LD.MULT R0 LR10 {{ cr.tmp }} ;;{% endif %}
 {% for h in range(2) %}
 {% if h == 0 and i %}ADDBI LRD0 -63 ;{% elif h == 1 %}ADDBI LRD0 -64 ;{% endif %} SET LR2 {{ cr.c128 }} ; SET LR3 {{ cr.cC }} ;
 {% for j in range(8 if h == 0 else channels // 16 - 8) %}
  {% if j %}ADDBI LRD0 -64 ; ADDBI LRD2 8 ; {% endif %}
  {% if channels == 144 and h == 0 %}{% if j == 1 and i %}{% if i == 4 %}SET LR9 LR14 ;{% else %}ADD LR9 LR9 LR13 ;{% endif %}{% elif j == 2 %}ADD LR8 LR9 CR1 ;{% endif %}{% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD0 64 ; ADDBI LRD2 8 ;
  {% if not loop.last or h == 0 %}INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;{% elif channels == 144 and i < 7 %}SET LR10 LR4 ; LD.MULT R0 LR10 {{ cr.tmp }} ;{% endif %}
 MULT.VE LR12 CR1 0 LR12 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;
  {% if loop.last %}{% if h == 1 and channels != 144 %}INC LR9 1 ;{% endif %}ACTIVATE.QUANTIZE identity {{ 'CR15.L' if h == 0 else cr.dsl ~ '.L' }} {{ q }} {{ cr.tmp }} {{ 'LR8' if channels == 144 and h == 1 else 'LR9' }} ;{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {% endmacro %}
 {% for i in range(8) %}{{ unpack(i) }}{% endfor %}
 INC LR4 {{ channels // 16 }} ; DEC LR11 1 ;;
 ADD LR9 LR14 LR15 ; BNE LR11 CR0 unpack_tile ;;
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
   ADD LR12 LR4 LR3 ; INC LR8 32 ;;
  {{ at('LR6',27) }}
 {{ at('LR7',9) }}
  {{ at('LR13',rows) }}
   {{ at('LR11',8) }}
  SET LR15 LR2 ;;
 {% if channels == 144 %}
 {% set one = cr.ds1 ~ '.L' %}
 {% set wide = cr.ds1 ~ '.H' %}
 {# Retain both input halves in cyclic registers through the mean reduction.
    Encode the leading mean before adding the correction, then recover the
    residual. Apply the same schedule to gamma times inverse deviation. #}
 LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR4 ;;
 row_loop_fast:
 ADD LR5 LR14 CR1 ; LD.MULT R0 LR0 {{ cr.crow }} ; DEC LR13 1 ;;
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM.FIRST LR0 CR15.L ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR12 ;;
 MULT.RC.VV LR12 R0 0 LR0 {{ cr.dsl }}.L {{ q }} ; AGG.SUM LR0 {{ cr.dsl }}.L ; SET LR1 CR1 ; LD.MULT R0 LR1 {{ cr.crow }} ; ACTIVATE.QUANTIZE identity {{ one }} {{ wide }} {{ cr.tmp }} LR6 ;;
 MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ; SET LR9 LR8 ; LD.MULT R1 LR6 {{ cr.tmp }} ;;
 MULT.RC.VV LR12 R0 0 LR0 {{ cr.dsl }}.L {{ q }} ; AGG.SUM LR0 {{ cr.dsl }}.L ; ADD LR1 LR6 CR1 ;;
 MULT.EE LR3 CR1 0 LR0 {{ one }} {{ wide }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ one }} {{ wide }} {{ cr.tmp }} LR1 ;;
 {% for h in range(2) %}
 {% set ds = 'CR15.L' if h == 0 else cr.dsl ~ '.L' %}
 MULT.RC.VE {{ 'LR4' if h == 0 else 'LR12' }} CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST {% if h %}; INC LR9 1{% else %}; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 MULT.EE LR3 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ;;
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ cr.tmp }} LR9 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} {{ 'LR0' if h == 0 else 'LR3' }} ;;
 MULT.RC.VE {{ 'LR0' if h == 0 else 'LR3' }} CR1 0 LR0 {{ ds }} {{ wide }} ; ACC.SUB ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ wide }} {{ cr.tmp }} LR9 {% if h == 1 %}; SET LR10 CR0{% endif %} ;;
 {% endfor %}
 MULT.RC.VS LR0 0 LR0 CR15.L {{ wide }} ; AGG.SUM.FIRST LR0 CR15.L ; LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR4 ;;
 MULT.RC.VS LR3 0 LR0 CR15.L {{ wide }} ; AGG.SUM LR0 CR15.L ; LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar(ds=one,tail='; ACTIVATE.QUANTIZE rsqrt ' ~ one ~ ' ' ~ wide ~ ' ' ~ cr.tmp ~ ' LR11') }}
 LD.MULT R1 LR11 {{ cr.tmp }} ; SET LR5 LR8 ; ADD LR1 LR7 CR1 ;;
 {% for h in range(2) %}
 MULT.RC.VE LR4 LR3 0 LR0 CR15.L {{ wide }} ; ACC.ADD.FIRST ; INC LR10 2 ; LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR4 ; ACTIVATE.QUANTIZE identity CR15.L {{ wide }} {{ cr.tmp }} LR7 ;;
 MULT.RC.VE LR4 LR3 0 LR0 CR15.L {{ wide }} ; ACC.ADD ; LD.MULT R0 LR7 {{ cr.tmp }} ; SET LR10 {{ 'CR0' if h == 0 else 'CR1' }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ wide }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity CR15.L {{ wide }} {{ cr.tmp }} LR1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR12 ;;
 MULT.RC.VV LR12 R0 0 LR0 CR15.L {{ wide }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV {{ 'LR0' if h == 0 else 'LR3' }} R0 0 LR0 CR15.L {{ wide }} ; ACC.ADD ; LD.MULT R0 LR7 {{ cr.tmp }} ;;
 MULT.RC.VV {{ 'LR0' if h == 0 else 'LR3' }} R0 0 LR0 CR15.L {{ wide }} ; ACC.ADD ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta) }}
  {{ scalar(tail='; INC LR15 1 ; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ (' CR15.L ' if h == 0 else ' ' ~ cr.dsl ~ '.L ') ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR15' ~ (' ; INC LR5 1 ; SET LR10 CR1 ; LD.MULT.CYCLIC LR10 ' ~ cr.gamma ~ ' LR4' if h == 0 else ' ; INC LR14 2 ; LD.MULT.CYCLIC LR14 ' ~ cr.tmp ~ ' LR4 ; BNE LR13 CR0 row_loop_fast')) }}
 {% endfor %}
 {% else %}
 row_loop:
   {% set one = cr.ds1 ~ '.L' %}
   {% set qgain = cr.ds1 ~ '.H' %}
 {# Normalize while summing, rather than encoding and reloading the sum. #}
  SET LR1 CR0 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR0 ; SET LR5 LR14 ;;
  DEC LR13 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
   {% set slots = ['LR0','LR3'] %}
  {% set halves = ['CR15.L',cr.dsl ~ '.L'] %}
  {% for slot in slots %}
  {% set s = loop.index0 %}
  {% for i in range(2) %}
  {% set ds = halves[(s+i)%2] %}
   {% if i == 0 %}{{ 'DEC' if s % 2 else 'INC' }} LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ; {% elif s + 1 < slots|length %}INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.crow }} {{ slots[s+1] }} ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM{% if s == 0 and i == 0 %}.FIRST{% endif %} LR0 {{ ds }} ;;
 {% endfor %}
 {% endfor %}
  {# Keep the mean in lane zero and broadcast each piece at subtraction. #}
   SET LR1 LR6 ; SET LR5 LR14 ; SET LR9 LR8 ; ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
   LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {{ scalar('SUB',tail='; INC LR1 1 ; LD.MULT R0 LR5 ' ~ cr.tmp ~ ' ; ACTIVATE.QUANTIZE identity CR15.L ' ~ q ~ ' ' ~ cr.tmp ~ ' LR1') }}
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
  SET LR1 LR6 ; {% if not loop.first %}DEC LR9 1 ; {% endif %}MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   {% for n in range(2) %}
   MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %}ACTIVATE.QUANTIZE identity {{ ds }} {{ qgain }} {{ cr.tmp }} LR9{% endif %} ;;
  {% endfor %}
   LD.MULT R0 LR9 {{ cr.tmp }} ;;
   MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qgain }} ; ACC.SUB ; INC LR9 2 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ qgain }} {{ cr.tmp }} LR9 {% if loop.first %}; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}

   {# Use the leading centered pieces for variance; retain both for the affine pass. #}
   LD.MULT.CYCLIC LR8 {{ cr.tmp }} LR0 ;;
   DEC LR9 2 ; MULT.RC.VS LR0 0 LR0 CR15.L {{ qgain }} ; AGG.SUM.FIRST LR0 CR15.L ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
   MULT.RC.VS LR3 0 LR0 CR15.L {{ qgain }} ; AGG.SUM LR0 CR15.L ; LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {# Work in sum-of-squares units: epsilon and gamma compensate in fold(). #}
   {# Take the reciprocal square root directly in sum-of-squares units. #}
   {{ scalar(ds=one,tail='; SET LR5 LR8 ; SET LR10 CR0 ; LD.MULT.CYCLIC LR10 ' ~ cr.gamma ~ ' LR0 ; ACTIVATE.QUANTIZE rsqrt ' ~ one ~ ' ' ~ qgain ~ ' ' ~ cr.tmp ~ ' LR11') }}
   LD.MULT R1 LR11 {{ cr.tmp }} ;;
 {% for h in range(2) %}
   {% for i in range(2) %}
      MULT.RC.VE LR0 LR3 0 LR0 CR15.L {{ qgain }} ; ACC.ADD{% if i==0 %}.FIRST{% endif %} ; {% if not loop.last %}INC LR10 2 ; LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0{% else %}SET LR1 LR7 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR4 ; ACTIVATE.QUANTIZE identity CR15.L {{ qgain }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
  {# Keep inverse in R1. Use both linear corrections, omitting the product of residuals. #}
   INC LR5 2 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   MULT.VE LR0 CR1 0 LR0 CR15.L {{ qgain }} ; ACC.SUB ; INC LR1 1 ; ACTIVATE.QUANTIZE identity CR15.L {{ qgain }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR12 ;;
   MULT.RC.VV LR12 R0 0 LR0 CR15.L {{ qgain }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ qgain }} ; ACC.ADD ; DEC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
   MULT.RC.VV LR4 R0 0 LR0 CR15.L {{ qgain }} ; ACC.ADD ; DEC LR5 1 ; SET LR10 {{ 'CR0' if h == 0 else 'CR1' }} ; LD.MULT R0 LR10 {{ cr.beta }} ;;
  {% for i in range(2) %}
     {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta if not loop.last else '; INC LR15 1 ; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ (' CR15.L ' if h == 0 else ' ' ~ cr.dsl ~ '.L ') ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR15' ~ (' ; SET LR10 CR1 ; LD.MULT.CYCLIC LR10 ' ~ cr.gamma ~ ' LR0' if h == 0 else ' ; INC LR14 2 ; BNE LR13 CR0 row_loop')) }}
   {% endfor %}
  {% endfor %}
 {% endif %}
  HALT ;;
