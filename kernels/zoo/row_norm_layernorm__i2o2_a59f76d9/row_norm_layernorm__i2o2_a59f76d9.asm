{% set q = cr.qf_in0 ~ '.L' %}
{% macro load(n,cy=false) %}
 SET LR1 CR0 ;;
 {% if cy %} INC LR1 {{ n }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %} INC LR1 {{ n }} ; LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',ds='CR15.L',x='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ x }} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0',op='ADD',x='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 CR15.L {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} {{ x }} ;;
{% endmacro %}
{% macro encode(reg,pieces,ds='CR15.L',pre='') %}
 {% for i in range(pieces) %}
 {% if i == 0 %}
 {% if pre %}{{ pre }} ; {% endif %}ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% else %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB',ds=ds) }}
 INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 SET LR1 CR0 ;;
 {{ encode('LR1',pieces,pre='INC LR1 ' ~ n) }}
{% endmacro %}
{% macro center_body(ds) %}
 {{ scalar(first=true,ds=ds) }}
 {% for n in range(27,30) %}{{ load(n) }}{{ scalar('SUB',ds=ds) }}{% endfor %}
 {{ encode('LR9',3,ds) }}
{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 CR15.L {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 {{ scalar(first=true,imm='CR0',x='; INC LR7 3') }}
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for j in range(3,6) %}{{ load(j) }}{{ mul(x='; INC LR10 1' if loop.last else '') }}{% endfor %}
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}
 {{ load(b) }}{{ mul(first=(i==0)) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% endfor %}
 {% if a == 11 %}{{ load(22,true) }}{{ load(b) }}{{ mul() }}{% endif %}
 {{ save(dest) }}
{% endmacro %}




{% set eu = namespace(a=rows, b=channels) %}
{% for _ in range(24) %}{% if eu.b %}{% set t = eu.b %}{% set eu.b = eu.a % eu.b %}{% set eu.a = t %}{% endif %}{% endfor %}
{% set g = eu.a %}
{% set T = channels // g %}
{% set M = g %}
{% set R = rows // g %}
{% set Pm = rows % channels %}
{% set Pq = rows // channels %}
{% set rstep = 2 * R %}
{% set r = 127 % T %}
{% set mh = [127 // T + 1, 127 // T] %}
{% macro setc(reg,v) %}
 SET {{ reg }} CR0 ;;
 {% for k in range(v // 255) %} INC {{ reg }} 255 ;;
 {% endfor %}{% if v % 255 %} INC {{ reg }} {{ v % 255 }} ;;{% endif %}
{% endmacro %}
{% macro adj(reg,d) %}
 {% if d > 0 %}{% for k in range(d // 255) %} INC {{ reg }} 255 ;;
 {% endfor %}{% if d % 255 %} INC {{ reg }} {{ d % 255 }} ;;{% endif %}
 {% elif d < 0 %}{% for k in range((-d) // 255) %} DEC {{ reg }} 255 ;;
 {% endfor %}{% if (-d) % 255 %} DEC {{ reg }} {{ (-d) % 255 }} ;;{% endif %}{% endif %}
{% endmacro %}
{% macro group(lab,ja,jb,n,mhi,h) %}
 {{ setc('LR14', jb) }}
 SET LR11 CR0 ;;
 {{ adj('LR11', ja) }}
{{ lab }}_loop:
 SET LR10 LR7 ; SET LR6 LR8 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR12 CR0 ;;
 ADDB LRD2 LR11 ; BLT.S LR8 {{ cr.c128 }} {{ lab }}_lo ;;
 INC LR10 1 ; SUB LR6 LR8 {{ cr.c128 }} ;;
{{ lab }}_lo:
 {% set L0 = T * mhi - 128 * h %}
 {% for k in range((L0 + 126) // 127) %} ADDBI LRD2 {{ [127, L0 - 127 * k]|min }} ;;
 {% endfor %}
 {{ adj('LR12', n) }}
{{ lab }}_elem:
 DEC LR10 {{ rstep }} ; ADDBI LRD2 -{{ T }} ; DEC LR12 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
 MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; BNE LR12 CR0 {{ lab }}_elem ;;
 INC LR7 {{ Pq * 2 }} ; INC LR8 {{ Pm }} ; INC LR11 1 ;;
 BLT.S LR8 {{ cr.cC }} {{ lab }}_nw ;;
 SUB LR8 LR8 {{ cr.cC }} ; INC LR7 2 ;;
{{ lab }}_nw:
 BNE LR11 LR14 {{ lab }}_loop ;;
{% endmacro %}

 {# ---- gather: out(p,c) = flat[p + rows*c] of the stored [4,n1,C] (in0: lanes = dim 2, rows [0,1]); c = j + T*m ---- #}
 SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
 {{ setc('LR1', rows) }}
 {{ setc('LR9', 40) }}
 {{ setc('LR13', rows // 2) }}
p_loop:
 {% for h in range(2) %}
 SET LR7 LR4 ; SET LR8 LR5 ;;
 {% set ns = namespace(prev=0) %}
 {% for sg in range(2) %}
 {% set ja = 0 if sg == 0 else r + 1 %}
 {% set jb = r + 1 if sg == 0 else T %}
 {% if jb > ja %}
 {% set m0 = mh[sg] %}
 {% set mhi = m0 if h == 0 else M %}
 {% set n = m0 if h == 0 else M - m0 %}
 {% if n > 0 %}
 {{ adj('LR7', rstep * mhi - ns.prev) }}
 {% set ns.prev = rstep * mhi %}
 {{ group('g%d%d' % (h, sg), ja, jb, n, mhi, h) }}
 {% endif %}
 {% endif %}
 {% endfor %}
 {% if h == 0 %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR9 ;;
 ADD LR15 LR9 CR1 ;;
 {% else %}
 ACTIVATE.QUANTIZE identity CR14.L {{ q }} {{ cr.tmp }} LR15 ;;
 {% endif %}
 {% endfor %}
 ADD LR9 LR9 LR13 ; INC LR5 1 ; DEC LR1 1 ;;
 BLT.S LR5 {{ cr.cC }} p_nw ;;
 SUB LR5 LR5 {{ cr.cC }} ; INC LR4 2 ;;
p_nw:
 SET LR15 CR0 ;;
 INC.MODP2 LR15 LR1 2 ;;
 BNE LR15 CR0 p_noe ;;
 SUB LR9 LR9 LR13 ;;
 SUB LR9 LR9 LR13 ;;
 SUB LR9 LR9 LR13 ;;
 SUB LR9 LR9 LR13 ;;
 INC LR9 2 ;;
p_noe:
 BNE LR1 CR0 p_loop ;;

 {# ---- layer norm over the gathered rows ---- #}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 DEC LR2 1 ; INC LR3 128 ; SET LR14 CR0 ;;
 ADD LR4 LR3 LR3 ; INC LR14 40 ; SET LR8 CR0 ;;
 ADD LR12 LR4 LR3 ; INC LR8 3 ;;
 {{ setc('LR13', rows) }}
row_loop:
 MULT.VE LR0 CR0 0 LR0 CR15.L {{ q }} ; ACC.ADD.FIRST ; SET LR5 LR14 ; DEC LR13 1 ;;
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ q }} ; AGG.SUM LR0 CR15.L ;;
 INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR14.L {{ q }} ; AGG.SUM LR0 CR14.L ;;
 {{ average('mean_scale') }}{{ save(27,3) }}

 SET LR5 LR14 ; SET LR9 CR0 ;;
 INC LR9 32 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ center_body('CR15.L') }}
 INC LR5 1 ; INC LR9 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ center_body('CR14.L') }}

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
 {{ scalar() }}
 SET LR1 CR0 ;;
 INC LR1 8 ;;
 ACTIVATE.QUANTIZE rsqrt CR15.L {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }}{{ save(22,1) }}

 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {{ save(17) }}
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
 {% for n in range(19,22) %}{{ load(n) }}{{ mul(x='; INC LR10 2 ; INC LR7 1' if loop.last else '') }}{% endfor %}
 BLT.S LR7 LR8 weight_loop ;;
 {{ save(9,3) }}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 {% for n,slot in [(27,'LR3'),(28,'LR4'),(29,'LR12')] %}
 {{ load(n,true) if false else '' }}
 SET LR1 CR0 ;;
 INC LR1 {{ n }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }} ;;
 {% endfor %}
 {{ scalar(first=true,imm='CR0') }}
 SET LR1 CR0 ; SET LR7 CR0 ;;
 INC LR1 9 ; INC LR7 12 ;;
apply_weight:
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}
 {% for slot in ['LR3','LR4','LR12'] %}{{ mul(slot=slot,op='SUB',x='; INC LR1 1' if loop.last else '') }}{% endfor %}
 BLT.S LR1 LR7 apply_weight ;;
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ scalar(x=('; INC LR10 2 ; INC LR11 1 ; INC LR5 1' if loop.last else '; INC LR10 2')) }}
 {% endfor %}
 INC LR15 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ; BLT.S LR5 LR6 output_loop ;;
 SET LR2 LR15 ; INC LR14 2 ; BNE LR13 CR0 row_loop ;;
 HALT ;;
