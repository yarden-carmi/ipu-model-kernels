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
{% macro group(seg,base,n,bound) %}
{{ seg }}_loop:
 SET LR10 LR7 ; SET LR6 LR8 ; SET LR2 CR0 ;;
 SET LR3 CR0 ; SET LR12 CR0 ;;
 ADDBI LRD2 {{ base }} ; BLT.S LR8 {{ cr.c128 }} {{ seg }}_lo ;;
 INC LR10 1 ; SUB LR6 LR8 {{ cr.c128 }} ;;
{{ seg }}_lo:
 ADDB LRD2 LR11 ;;
 {% if n > 1 %}INC LR12 {{ n }} ;;{% else %}INC LR12 1 ;;{% endif %}
{{ seg }}_elem:
 DEC LR10 128 ; ADDBI LRD2 -9 ; DEC LR12 1 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
 MULT.EE LR6 CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; BNE LR12 CR0 {{ seg }}_elem ;;
 INC LR7 14 ; INC LR8 16 ; INC LR11 1 ;;
 BLT.S LR8 {{ cr.c144 }} {{ seg }}_nw ;;
 SUB LR8 LR8 {{ cr.c144 }} ; INC LR7 2 ;;
{{ seg }}_nw:
 BNE LR11 LR14 {{ seg }}_loop ;;
{% endmacro %}


{% set Q = channels // 4 %}
{% macro setc(reg,v) %}
 SET {{ reg }} CR0 ;;
 {% for k in range(v // 255) %} INC {{ reg }} 255 ;;
 {% endfor %}{% if v % 255 %} INC {{ reg }} {{ v % 255 }} ;;{% endif %}
{% endmacro %}
{% set widx = {0:'LR0',1:'LR1',2:'LR12',3:'LR13'} %}
{% set capr = {1:'LR10',2:'LR11',3:'LR14'} %}
{% macro eloop(label,w,n,dest0,start,cap) %}
 SUB LR7 {{ start }} LR6 ; SET LR8 CR0 ; {% if dest0 == 0 %}SUB LR3 LR0 CR1{% else %}SET LR3 CR0{% endif %} ;;
 INC LR8 {{ n }} {% if dest0 > 0 %}; ADDBI LRD2 {{ dest0 - 1 }}{% endif %} ;;
{{ label }}:
 LD.MULT R0 LR7 {{ cr.in0 }} ; ADD LR3 LR3 {{ cr.c24 }} ; ADD LR7 LR7 LR6 ; DEC LR8 1 ;;
 MULT.EE {{ widx[w] }} CR1 0 LR0 CR15.L {{ q }} ; ACC.RESHAPE LRD0 LRD2 7 ; BNE LR8 CR0 {{ label }} ;;
 {% if cap %}ADD {{ cap }} LR7 LR6 ;;{% endif %}
{% endmacro %}

 {# ---- gather: out(p,c) with c = Q*w + u is lane w of in0 row p + rows*u (in0: lanes = dim 0, rows [1,2]) ---- #}
 SET LR0 CR0 ; SET LR1 CR1 ; SET LR4 CR0 ;;
 SET LR12 CR1 ; SET LR13 CR1 ; SET LR15 CR0 ;;
 INC LR12 1 ; INC LR13 2 ;;
 {{ setc('LR6', rows) }}
 {{ setc('LR9', rows // 2) }}
 {{ setc('LR5', 40) }}
p_loop:
 {% for h in range(2) %}
 {% for w in range(4) %}
 {% set lo = [0, 128 * h - Q * w]|max %}
 {% set hi = [Q, 128 * (h + 1) - Q * w]|min %}
 {% if hi > lo %}
 {% set start = 'LR4' if lo == 0 else capr[w] %}
 {% set nxt = (h == 0 and hi < Q) %}
 {{ eloop('g%d%d' % (h, w), w, hi - lo, Q * w + lo - 128 * h, start, capr[w] if nxt else '') }}
 {% endif %}
 {% endfor %}
 {% if h == 0 %}
 ACTIVATE.QUANTIZE identity CR15.L {{ q }} {{ cr.tmp }} LR5 ;;
 {% else %}
 ADD LR2 LR5 CR1 ;;
 ACTIVATE.QUANTIZE identity CR14.L {{ q }} {{ cr.tmp }} LR2 ;;
 {% endif %}
 {% endfor %}
 INC.MODP2 LR15 CR1 2 ; ADD LR5 LR5 LR9 ; INC LR4 1 ;;
 BNE LR15 CR0 p_nw ;;
 SUB LR5 LR5 LR6 ;;
 SUB LR5 LR5 LR6 ;;
 INC LR5 2 ;;
p_nw:
 BLT.S LR4 LR6 p_loop ;;

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
