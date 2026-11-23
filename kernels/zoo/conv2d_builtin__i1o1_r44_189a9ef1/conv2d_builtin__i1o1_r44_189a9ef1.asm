{% set wo = (w - 1) // stride + 1 %}
{% set ho = (h - 1) // stride + 1 %}
{% set right = (wo - 1) * stride == w - 1 %}
{% set bottom = (ho - 1) * stride == h - 1 %}
{% set inner = wo - 1 - right|int %}
{% macro step(r,n) %}
{% for k in range(0,n,255) %} INC {{r}} {{[255,n-k]|min}} ;;
{% endfor %}
{% endmacro %}

{# LR0/LR1 stream the two weight parts; LR2/LR3 pin the bias parts.
   LR5 is the input center, LR6 the tap address, LR7 the weight stream.
   LR13 tracks the first tap address in the interior pipeline. The first
   multiply advances it; the bias multiply prefetches from it. The final
   prefetch is safe even without a right-edge output: it reads x = w-1. #}
{% macro pixels(tag, ys, ye, xs, xe, pipe=false) %}
{% set ns = namespace(taps=[]) %}
{% for y in range(ys,ye) %}{% for x in range(xs,xe) %}
{% set ns.taps = ns.taps + [3*y+x] %}
{% endfor %}{% endfor %}
{% set ts = ns.taps %}
{% set first = ts[0] %}
{% macro gap(a,b) %}{{ (b//3-a//3)*w + b%3-a%3 }}{% endmacro %}
{% set offset = (1-first//3)*w+1-first%3 %}
 {% if offset %}SUB LR6 LR5 {{ {1:'CR1',w:cr.width,w+1:cr.width_plus_one}[offset] }}{% else %}SET LR6 LR5{% endif %} ; SET LR7 CR0 ; SET LR9 CR0 ;;
 LD.MULT R0 LR6 {{ cr.in0 }}{% if first %} ; INC LR7 {{ 2*first }}{% endif %}{% if pipe %} ; SET LR13 LR6{% endif %} ;;
 LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0{% if pipe %} ; SET LR14 LR7{% endif %} ;;
 LD.MULT.CYCLIC LR7 {{ cr.weights }} LR1 ; INC LR7 1{% if pipe %} ; ADD LR15 LR14 CR1{% endif %} ;;
{{ tag }}:
{% for t in ts %}
{% set i = loop.index0 %}
 MULT.RC.VV LR0 R0 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; {{ 'ACC.ADD.FIRST' if loop.first else 'ACC.ADD' }}{% if not loop.last %} ; LD.MULT.CYCLIC LR7 {{ cr.weights }} LR0 ; INC LR7 {{ 2*(ts[i+1]-t)-1 }}{% elif pipe %} ; LD.MULT.CYCLIC LR14 {{ cr.weights }} LR0{% endif %}{% if loop.first %} ; INC LR5 {{ stride }}{% if pipe %} ; INC LR13 {{ stride }}{% endif %}{% endif %} ;;
 MULT.RC.VV LR1 R0 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; ACC.ADD{% if not loop.last %} ; LD.MULT.CYCLIC LR7 {{ cr.weights }} LR1 ; INC LR7 1{% elif pipe %} ; LD.MULT.CYCLIC LR15 {{ cr.weights }} LR1{% endif %}{% if pipe and loop.first %} ; INC LR9 1{% endif %} ;;
{% if not loop.last %}
 LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 {{ gap(t,ts[i+1]) }} ;;
{% endif %}
{% endfor %}
 MULT.RC.VE LR2 CR1 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; ACC.ADD{% if pipe %} ; LD.MULT R0 LR13 {{ cr.in0 }} ; SET LR6 LR13 ; SET LR7 LR15{% endif %} ;;
 MULT.RC.VE LR3 CR1 0 LR0 {{ cr.dsc }}.L {{ cr.qf_weights }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.dsc }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ; INC LR8 1{% if pipe %} ; BLT.S LR9 LR10 {{ tag }}{% endif %} ;;
{% endmacro %}

{% macro row(tag,ys,ye) %}
 {{ pixels(tag ~ '_left',ys,ye,1,3) }}
 {% if inner > 0 %}
 {{ pixels(tag ~ '_inner',ys,ye,0,3,true) }}
 {% endif %}
 {% if right %}
 {{ pixels(tag ~ '_right',ys,ye,0,2) }}
 {% endif %}
{% endmacro %}

 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 INC LR1 128 ; INC LR2 255 ; SET LR3 CR0 ;;
 INC LR2 1 ; INC LR3 255 ; SET LR7 CR0 ;;
 INC LR3 129 ; INC LR7 17 ; SET LR5 CR0 ;;
 LD.MULT.CYCLIC LR7 {{ cr.weights }} LR2 ; INC LR7 1 ; SET LR8 CR0 ;;
 LD.MULT.CYCLIC LR7 {{ cr.weights }} LR3 ; INC LR7 1 ; DEC LR8 1 ; SET LR10 CR0 ;;
 {{ step('LR10',inner) }}
 {{ row('top',1,3) }}
 {{ step('LR5',stride*(w-wo)) }}
{% set mid = ho - 1 - bottom|int %}
{% if mid > 0 %}
 SET LR11 CR0 ; SET LR12 CR0 ;;
 {{ step('LR12',mid-1) }}
middle:
 {{ row('mid',0,3) }}
 {{ step('LR5',stride*(w-wo)) }}
 INC LR11 1 ; BLT.S LR11 LR12 middle ;;
{% endif %}
{% if bottom %}
 {{ row('bottom',0,2) }}
{% endif %}
 HALT ;;
