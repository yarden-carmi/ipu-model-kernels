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
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds='CR15.L',tail='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',tail='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ tail }} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds='CR15.L') %}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds,tail='; INC ' ~ reg ~ ' 1') }}
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0',tail='; INC LR7 3') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul(tail='; INC LR10 1' if loop.last else '') }}{% endfor %}
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}{{ load(b) }}{{ mul(first=(i==0)) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}

{# Gather the strided view in output row order by grouping fixed source lanes. #}
{% set eu = namespace(a=rows, b=channels) %}
{% for _ in range(24) %}{% if eu.b %}{% set t = eu.b %}{% set eu.b = eu.a % eu.b %}{% set eu.a = t %}{% endif %}{% endfor %}
{% set M = eu.a %}
{% set T = channels // M %}
{% set step = 2 * (rows // M) %}
{% set r = 127 % T %}
{% macro group(label,ja,jb,n,mhi,h) %}
 {{ at('LR14',jb) }}{{ at('LR11',ja) }}
{{ label }}_group:
 SET LR10 LR7 ; SET LR6 LR8 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR12 CR0 ;;
 ADDB LRD2 LR11 ; BLT.S LR8 {{ cr.c128 }} {{ label }}_low ;;
 INC LR10 1 ; SUB LR6 LR8 {{ cr.c128 }} ;;
{{ label }}_low:
 {% set offset = T * mhi - 128 * h %}
 {% for k in range((offset + 126) // 127) %}ADDBI LRD2 {{ [127,offset - 127 * k]|min }} ;;{% endfor %}
 {% if step <= 255 and T <= 128 %}
 {# Prime R0, then load the next source row while scattering the current one. #}
 DEC LR10 {{ step }} ; LD.MULT R0 LR10 {{ cr.in0 }}{% if n > 1 %} ; INC LR12 {{ n - 1 }}{% endif %} ;;
 {% if n > 1 %}
 {{ label }}_pipe:
 DEC LR10 {{ step }} ; ADDBI LRD2 -{{ T }} ; DEC LR12 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ; MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; BLT.S CR1 LR12 {{ label }}_pipe ;;
 {% endif %}
 ADDBI LRD2 -{{ T }} ; MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
 {% else %}
 {{ adj('LR12',n) }}
{{ label }}_elem:
 {% if step > 255 %}{{ adj('LR10',-step) }}{% endif %}
 {% if T > 128 %}ADDBI LRD2 -128 ;;{% endif %}
 {% if step <= 255 %}DEC LR10 {{ step }} ; {% endif %}ADDBI LRD2 -{{ T if T <= 128 else T - 128 }} ; DEC LR12 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
 MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; BNE LR12 CR0 {{ label }}_elem ;;
 {% endif %}
 {% if 2 * (rows // channels) %}INC LR7 {{ 2 * (rows // channels) }} ; {% endif %}{% if rows % channels %}INC LR8 {{ rows % channels }} ; {% endif %}INC LR11 1 ;;
 BLT.S LR8 {{ cr.cC }} {{ label }}_next ;;
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
 {{ adj('LR7',step * hi - ns.prev) }}
 {% set ns.prev = step * hi %}
 {{ group('g%d%d' % (h,seg),ja,jb,n,hi,h) }}
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
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
 {% if not loop.first %}INC LR5 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 {{ average('mean_scale') }}{{ save(27,3) }}

 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
 {% for ds in ['CR15.L',cr.dsl ~ '.L'] %}
 {% if not loop.first %}INC LR5 1 ; INC LR9 1 ; {% endif %}LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ scalar(first=true,ds=ds) }}
 {% for n in range(27,30) %}{{ load(n) }}{{ scalar('SUB',ds=ds) }}{% endfor %}
 {{ encode('LR9',3,ds) }}
 {% endfor %}

 SET LR5 CR0 ; SET LR9 CR0 ; SET LR6 CR0 ;;
 INC LR9 32 ; INC LR6 2 ;;
 {{ scalar(first=true,imm='CR0') }}
variance_loop:
 SET LR1 LR9 ; ADD LR7 LR9 LR8 ;;
variance_parts:
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; SET LR10 LR9 ;;
variance_products:
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ; INC LR10 1 ;;
 BLT.S LR10 LR7 variance_products ;;
 INC LR1 1 ;;
 BLT.S LR1 LR7 variance_parts ;;
 SET LR9 LR7 ; INC LR5 1 ;;
 BLT.S LR5 LR6 variance_loop ;;
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }}{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {# Refine the approximate inverse standard deviation twice. #}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 CR15.L {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }}{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(21,1) }}

 SET LR5 LR14 ; SET LR15 LR2 ; SET LR11 CR0 ;;
 SET LR6 LR14 ;;
 INC LR6 2 ;;
output_loop:
 SET LR10 LR11 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0') }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in range(19,22) %}{{ load(n) }}{{ mul(tail='; INC LR10 2 ; INC LR7 1' if loop.last else '') }}{% endfor %}
 BLT.S LR7 LR8 weight_loop ;;
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 {% for n,slot in [(27,'LR3'),(28,'LR4'),(29,'LR12')] %}
 {{ at('LR1',n) }}LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 {{ scalar(first=true,imm='CR0') }}
 {{ at('LR1',9) }}{{ at('LR7',12) }}
apply_weight:
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% for slot in ['LR3','LR4','LR12'] %}{{ mul(slot=slot,op='SUB',tail='; INC LR1 1' if loop.last else '') }}{% endfor %}
 BLT.S LR1 LR7 apply_weight ;;
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar(tail='; INC LR11 1 ; INC LR5 1' if loop.last else '; INC LR10 2') }}
 {% endfor %}
 INC LR15 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ; BLT.S LR5 LR6 output_loop ;;
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
