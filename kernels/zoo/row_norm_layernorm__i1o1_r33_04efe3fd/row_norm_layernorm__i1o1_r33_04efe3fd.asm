{% set q = cr.qf_stats ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set slots = ['LR0', 'LR14', 'LR15'] %}
{% macro ptr(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD', first=false, fmt=q, scalar='CR1') %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro save(n, parts=3, p='LR10') %}
 {% if n is number %}{{ ptr(p,n) }}{% else %}SET {{ p }} {{ n }} ;;{% endif %}
 {% for i in range(parts) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ p }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ p }} {{ cr.tmp }} ;;
 {{ ve('SUB') }}
 INC {{ p }} 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro cyclic(n,parts=3) %}
 {% if n is number %}{{ ptr('LR10',n) }}{% else %}SET LR10 {{ n }} ;;{% endif %}
 {% for slot in slots[:parts] %}
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} {{ slot }} ;;
 {% if not loop.last %}INC LR10 1 ;;{% endif %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,base=cr.tmp,parts=3,other=3,first=true) %}
 {{ cyclic(a,parts) }}
 {% if b is number %}{{ ptr('LR11',b) }}{% else %}SET LR11 {{ b }} ;;{% endif %}
 LD.MULT R0 LR11 {{ base }} ;;
 {% for i in range(other) %}
 {% for slot in slots[:parts] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first and first %}.FIRST{% endif %}{% if loop.last and i < other-1 %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ base }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro average() %}
 {{ save(0) }}
 {{ product(0,0,cr.stats) }}
{% endmacro %}
{% macro reset() %}
 SET LR4 LR2 ; SET LR5 {{ cr.channels }} ;;
 {{ ptr('LR6',32) }}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR1 ;;
 SET LR14 CR0 ; SET LR15 CR0 ;;
 INC LR14 128 ;;
 ADD LR15 LR14 LR14 ;;
tile:
 {# Each lane is a separate logical row; channel words are stride apart. #}
 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
sum:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 sum ;;
 {{ average() }}
 {{ save(3) }}

 {{ reset() }}
center:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {{ ve(first=true,fmt=iq) }}
 {{ ptr('LR11',3) }}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ve('SUB') }}
 {% if not loop.last %}INC LR11 1 ;;{% endif %}
 {% endfor %}
 {{ save('LR6') }}
 INC LR6 3 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 center ;;

 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
variance:
 {{ product('LR6','LR6',first=false) }}
 INC LR6 3 ; DEC LR5 1 ;;
 BNE LR5 CR0 variance ;;
 {{ average() }}
 {{ ptr('LR11',3) }}
 LD.MULT R0 LR11 {{ cr.stats }} ;;
 {{ ve() }}
 {{ ptr('LR11',9) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR11 ;;
 {{ save(6) }}
 {{ product(6,4,cr.stats,other=1) }}
 {{ save(6) }}

 {# Refine the table seed without discarding the low bits of the inverse. #}
 {{ ptr('LR11',9) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ve(first=true) }}
 {{ save(9) }}
 SET LR12 CR0 ;;
 INC LR12 2 ;;
refine:
 {{ product(9,9) }}
 {{ save(12) }}
 {{ product(6,12) }}
 {{ save(15) }}
 {{ ptr('LR11',9) }}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ve(first=loop.first) }}
 INC LR11 1 ;;
 {% endfor %}
 {{ product(9,4,cr.stats,other=1,first=false) }}
 {# Keep the Newton subtraction in the accumulator: 1.5*y - 0.5*y*(v*y*y). #}
 {{ cyclic(9) }}
 {{ ptr('LR11',15) }}
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {% for slot in slots %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 INC LR11 1 ;;
 {% endfor %}
 {{ save(9) }}
 DEC LR12 1 ; BNE LR12 CR0 refine ;;

 {{ reset() }}
 SET LR7 CR0 ;;
output:
 {{ product(9,'LR6') }}
 {{ save(18) }}
 {{ product(18,'LR7',cr.affine) }}
 INC LR11 1 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR11 {{ cr.affine }} ;;
 {{ ve() }}
 INC LR11 1 ;;
 {% endfor %}
 SET LR7 LR11 ;;
 BEQ LR3 LR8 output_tail ;;
 {{ store(full) }}
 B output_next ;;
output_tail:
 {{ store(tail) }}
output_next:
 INC LR6 3 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 output ;;
 BEQ LR3 LR8 next_batch ;;
 INC LR3 1 ; INC LR2 1 ;;
 B tile ;;
next_batch:
 SUB LR2 LR4 LR8 ; SET LR3 CR1 ;;
 INC LR2 1 ;;
 BLT.S LR2 LR9 tile ;;
 HALT ;;
