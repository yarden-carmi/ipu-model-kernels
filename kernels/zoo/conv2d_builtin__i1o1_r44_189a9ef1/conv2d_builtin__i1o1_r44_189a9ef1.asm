{% set wo = (w-1)//stride+1 %}
{% set ho = (h-1)//stride+1 %}
{% set right = ((wo-1)*stride == w-1)|int %}
{% set bottom = ((ho-1)*stride == h-1)|int %}
{% set inner = wo-1-right %}
{% set paired = inner//2 %}
{% set ds = cr.active ~ '.L' %}
{% set q = cr.qf_weights ~ '.L' %}
{% macro move(r,n) %}{% if n > 0 %}INC {{r}} {{n}}{% elif n < 0 %}DEC {{r}} {{0-n}}{% endif %}{% endmacro %}
{% macro step(r,n) %}{% for k in range(0,n,255) %} INC {{r}} {{[255,n-k]|min}} ;;{% endfor %}{% endmacro %}
{% macro gap(a,b) %}{{ (b//3-a//3)*w+b%3-a%3 }}{% endmacro %}
{% macro weight(slot,delta) %}LD.MULT.CYCLIC LR7 {{cr.weights}} {{slot}}{% if delta %} ; {{move('LR7',delta)}}{% endif %}{% endmacro %}
{% macro product(slot,r,first=false) %}MULT.RC.VV {{slot}} {{r}} 0 LR0 {{ds}} {{q}} ; {{'ACC.ADD.FIRST' if first else 'ACC.ADD'}}{% endmacro %}
{% macro bias(slot) %}MULT.RC.VE {{slot}} CR1 0 LR0 {{ds}} {{q}} ; ACC.ADD{% endmacro %}
{% macro store() %}ACTIVATE.QUANTIZE {{act_out0}} {{ds}} {{cr.qf_out0}}.L {{cr.out0}} LR8 ; INC LR8 1{% endmacro %}
{% macro start(t) %}
 {% set off = (1-t//3)*w+1-t%3 %}
 {% if off == 0 %}SET LR6 LR5{% elif off < 0 %}ADD LR6 LR5 {{ {1:'CR1',w:cr.width,w+1:cr.width_plus_one}[-off] }}{% else %}SUB LR6 LR5 {{ {1:'CR1',w:cr.width,w+1:cr.width_plus_one}[off] }}{% endif %}
{% endmacro %}
{% macro edge(ys,ye,xs,xe) %}
 {% set ns=namespace(ts=[]) %}
 {% for y in range(ys,ye) %}{% for x in range(xs,xe) %}{% set ns.ts=ns.ts+[3*y+x] %}{% endfor %}{% endfor %}
 {% set ts=ns.ts %}
 {{start(ts[0])}} ; SET LR7 CR0 ;;
 LD.MULT R0 LR6 {{cr.in0}} ;;
 {{weight('LR0',2*ts[0])}} ;;
 {% for t in ts %}
 {% set i=loop.index0 %}
 {{product('LR0','R0',loop.first)}} ; {{weight('LR1',1)}}{% if loop.first %} ; INC LR5 {{stride}}{% endif %} ;;
 {{product('LR1','R0')}}{% if loop.last %} ; {{store()}}{% else %} ; {{weight('LR0',2*(ts[i+1]-t)-1)}}{% endif %} ;;
 {% if not loop.last %}
 LD.MULT R0 LR6 {{cr.in0}} ; {{move('LR6',gap(t,ts[i+1])|int)}}{% if i == 0 %} ; {{bias('LR2')}}{% elif i == 1 %} ; {{bias('LR3')}}{% endif %} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}

{# A pair walks the taps forward then backward. The last tap's two weight
   rows become the next pixel's first tap, and its final two multiplies fetch
   the next pixel's first two inputs. Bias uses two otherwise empty MULT slots. #}
{% macro piped(ts,branch='') %}
 {% for t in ts %}
 {% set i=loop.index0 %}
 {% set r='R1' if loop.first else 'R0' %}
 {% if not loop.last %}
 {{product('LR0',r,loop.first)}} ; {{weight('LR0',2*ts[i+1]-(2*ts[1] if loop.first else 2*t+1))}}{% if loop.first %} ; INC LR5 {{stride}}{% endif %} ;;
 {{product('LR1',r)}} ; {{weight('LR1',1)}} ;;
 {% if not loop.first %}
 LD.MULT R0 LR6 {{cr.in0}} ; {{move('LR6',gap(t,ts[i+1])|int)}}{% if i == 1 %} ; {{bias('LR2')}}{% elif i == 2 %} ; {{bias('LR3')}}{% endif %} ;;
 {% endif %}
 {% else %}
 {{product('LR0',r)}} ; LD.MULT R1 LR6 {{cr.in0}} ; INC LR6 {{stride}} ; SET LR7 {{'LR15' if branch else 'LR14'}} ;;
 {{product('LR1',r)}} ; LD.MULT R0 LR6 {{cr.in0}} ; {{move('LR6',gap(t,ts[i-1])|int)}} ; {{store()}}{% if branch %} ; INC LR9 1 ; BLT.S LR9 LR10 {{branch}}{% endif %} ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro row(tag,ys,ye) %}
 {{edge(ys,ye,1,3)}}
 {% if paired %}
 {# A's first two taps are in the left column, keeping the final
    speculative prefetch in bounds even on the last pair of a row. #}
 {% set ns=namespace(ts=[3*ys,3*(ys+1)]) %}
 {% for y in range(ys,ye) %}{% for x in range(1,3) %}{% set ns.ts=ns.ts+[3*y+x] %}{% endfor %}{% if y > ys+1 %}{% set ns.ts=ns.ts+[3*y] %}{% endif %}{% endfor %}
 {% set ts=ns.ts %}{% set rev=ts|reverse|list %}
 {{start(ts[0])}} ; SET LR7 CR0 ; SET LR9 CR0 ;;
 LD.MULT R1 LR6 {{cr.in0}} ; SET LR14 CR0 ; SET LR15 CR0 ;;
 {{weight('LR0',2*ts[0])}} ; INC LR14 {{2*rev[1]}} ;;
 {{weight('LR1',1)}} ; INC LR15 {{2*ts[1]}} ;;
 LD.MULT R0 LR6 {{cr.in0}} ; {{move('LR6',gap(ts[0],ts[1])|int)}} ; SET LR7 LR15 ;;
 {{tag}}_pair:
 {{piped(ts)}}
 {# Reverse body leaves the pointer at A's second weight for the backedge. #}
 {{piped(rev,tag ~ '_pair')}}
 {% endif %}
 {% if inner % 2 %}{{edge(ys,ye,0,3)}}{% endif %}
 {% if right %}{{edge(ys,ye,0,2)}}{% endif %}
{% endmacro %}

{% if cin == cout and cin == groups %}
 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 255 ; SET LR3 CR0 ;;
 INC LR2 1 ; INC LR3 255 ; SET LR7 CR0 ;;
 INC LR3 129 ; INC LR7 17 ; SET LR5 CR0 ;;
 {{weight('LR2',1)}} ; SET LR8 CR0 ; SET LR4 CR0 ;;
 {{weight('LR3',1)}} ; DEC LR8 1 ; SET LR10 CR0 ;;
 {% if paired > 1 %}INC LR10 {{paired-1}} ;;{% endif %}
batch:
 {{row('top',1,3)}}
 {{step('LR5',stride*(w-wo))}}
 {% set mid=ho-1-bottom %}
 {% if mid > 0 %}
 SET LR11 CR0 ; SET LR12 CR0 ;;
 {{step('LR12',mid-1)}}
middle:
 {{row('mid',0,3)}}
 {{step('LR5',stride*(w-wo))}}
 INC LR11 1 ; BLT.S LR11 LR12 middle ;;
 {% endif %}
 {% if bottom %}{{row('bottom',0,2)}}{% endif %}
 {% if bottom %}{% set wrap = w-stride*wo %}{% if wrap >= 0 %}{{step('LR5',wrap)}}{% else %}DEC LR5 {{0-wrap}} ;;{% endif %}{% endif %}
 INC LR4 1 ;;
 BLT.S LR4 {{cr.in0_d0}} batch ;;
{% endif %}
 HALT ;;
