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
{% macro encode(reg,pieces,ds='CR15.L') %}
 {% for i in range(pieces) %}
 {% if loop.first %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;{% endif %}
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,tail='; INC ' ~ reg ~ ' 1 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' ' ~ reg) }}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro broadcast_sum(next_load='') %}
 {{ save(0,3) }}
 SET LR1 CR0 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% for j in range(3) %}
 {% if not loop.last %}INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ; {% else %}{{ next_load }}{% endif %}MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {{ at('LR1',b-1) }}
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 {{ adj('LR1',a-b-1) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
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

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR2 1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
 ADD LR12 LR4 LR3 ; INC LR8 3 ;;
 {{ at('LR13',rows) }}
row_loop:
 {{ scalar(first=true,imm='CR0',tail='; SET LR5 LR14 ; DEC LR13 1') }}
 {# Normalize while summing, rather than encoding and reloading the sum. #}
 {% for slot in ['LR0','LR3','LR4'] %}
 {% if loop.first %}SET LR1 CR0 ; {% else %}INC LR1 1 ; {% endif %}LD.MULT.CYCLIC LR1 {{ cr.crow }} {{ slot }} ; SET LR5 LR14 ;;
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
 {% if loop.first %}INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {% endfor %}
 {{ broadcast_sum() }}{{ save(27,3) }}

 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
 {% if not loop.first %}INC LR5 1 ; INC LR9 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
 SET LR1 CR0 ; MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
 INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for n in range(2) %}{{ scalar('SUB',ds=ds,tail='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp) }}{% endfor %}
 {{ scalar('SUB',ds=ds,tail='; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR9') }}
 {% for n in range(2) %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,tail='; INC LR9 2 ; ACTIVATE.QUANTIZE identity ' ~ ds ~ ' ' ~ q ~ ' ' ~ cr.tmp ~ ' LR9') }}
 {% endfor %}
 DEC LR9 4 ;;
 {% endfor %}

 {{ scalar(first=true,imm='CR0',tail='; SET LR9 CR0') }}
 {% for h in range(2) %}
 {% for slot in ['LR0','LR3','LR4'] %}
 INC LR9 {{ (32 if h == 0 else 1) if loop.first else 2 }} ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} {{ slot }}{% if loop.first %} ; SET LR10 CR0{% endif %} ;;
 {% endfor %}
 INC LR10 {{ 32 + h }} ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for slot in ['LR0','LR3','LR4'] %}
 {% set last_slot = loop.last %}
 {% for i in range(3) %}
 {% if not (last_slot and loop.last) %}{{ 'DEC LR10 4' if loop.last else 'INC LR10 2' }} ; LD.MULT R0 LR10 {{ cr.tmp }} ; {% endif %}MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
 {% endfor %}
 {% endfor %}
 {% if h == 0 %}DEC LR9 4 ;;{% endif %}
 {% endfor %}
 {# Work in sum-of-squares units: epsilon and gamma compensate in fold(). #}
 {{ broadcast_sum('LD.MULT R0 LR0 ' ~ cr.epsilon ~ ' ; ') }}
 {{ scalar(tail='; SET LR1 CR0') }}
 INC LR1 8 ; ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Refine the approximate inverse standard deviation and keep three residual pieces. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19,3) }}

 SET LR5 LR14 ; SET LR15 LR2 ; SET LR11 CR0 ;;
 SET LR6 LR14 ;;
 INC LR6 1 ;;
output_loop:
 SET LR10 LR11 ; SET LR1 CR0 ;;
 INC LR1 19 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {{ mul(first=i==0) }}{{ mul(slot='LR3') }}
 {{ mul(slot='LR4',tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.gamma if not loop.last else '') }}
 {% endfor %}
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 SET LR1 CR0 ;;
 {% for slot in ['LR3','LR4','LR12'] %}
 INC LR1 {{ 27 if loop.first else 1 }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 DEC LR1 20 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {{ mul(first=loop.first) }}{{ mul(slot='LR3',op='SUB') }}{{ mul(slot='LR4',op='SUB') }}
 {{ mul(slot='LR12',op='SUB',tail='; INC LR1 1 ; LD.MULT R0 LR1 ' ~ cr.tmp if not loop.last else '; SET LR10 LR11 ; LD.MULT R0 LR10 ' ~ cr.beta) }}
 {% endfor %}
 {% for i in range(3) %}
 {{ scalar(tail='; INC LR10 2 ; LD.MULT R0 LR10 ' ~ cr.beta if not loop.last else '; INC LR11 1 ; INC LR15 1 ; INC LR5 1 ; ACTIVATE.QUANTIZE ' ~ (act_out0 | default('identity')) ~ ' CR15.L ' ~ cr.qf_out0 ~ '.L ' ~ cr.out0 ~ ' LR15 ; BLT.S LR5 LR6 output_loop') }}
 {% endfor %}
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
