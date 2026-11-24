{% set q = cr.qf_stats ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set slots = ['LR0', 'LR14', 'LR15', 'LR13'] %}
{% macro ptr(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD', first=false, fmt=q, scalar='CR1', extra='') %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}{{ extra }} ;;
{% endmacro %}
{% macro save(n, parts=4, p='LR10') %}
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
{% macro product(a,b,base=cr.tmp,parts=4,other=4,first=true,op='ADD') %}
 {{ cyclic(a,parts) }}
 {% if b is number %}{{ ptr('LR11',b) }}{% else %}SET LR11 {{ b }} ;;{% endif %}
 LD.MULT R0 LR11 {{ base }} ;;
 {% for i in range(other) %}
 {% for slot in slots[:parts] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if i == 0 and loop.first and first %}.FIRST{% endif %}{% if loop.last and i < other-1 %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ base }}{% endif %} ;;
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
{% macro accumulate_parts(n,base,first=false,op='ADD',count=3) %}
 {% if n is number %}{{ ptr('LR11',n) }}{% endif %}
 {% for i in range(count) %}
 LD.MULT R0 LR11 {{ base }} ;;
 {{ ve(op, first=first and loop.first, extra=' ; INC LR11 1') }}
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR1 ;;
 SET LR14 CR0 ; SET LR15 CR0 ;;
 INC LR14 128 ;;
 ADD LR15 LR14 LR14 ;;
 ADD LR13 LR15 LR14 ;;
tile:
 {# Each lane is a separate logical row; channels are stride apart. #}
 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
sum:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 sum ;;
 {{ average() }}
 {{ save(4) }}

 {{ reset() }}
center:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {{ ve(first=true,fmt=iq) }}
 {{ accumulate_parts(4,cr.tmp,op='SUB',count=4) }}
 {{ save('LR6') }}
 INC LR6 4 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 center ;;

 {{ reset() }}
 {{ ve(first=true,scalar='CR0') }}
variance:
 {{ product('LR6','LR6',first=false) }}
 INC LR6 4 ; DEC LR5 1 ;;
 BNE LR5 CR0 variance ;;
 {{ average() }}
 {{ accumulate_parts(4,cr.stats,count=4) }}
 {{ ptr('LR11',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR11 ;;
 {{ save(8) }}
 {{ product(8,8,cr.stats,other=1) }}
 {{ save(8) }}

 {# Refine the table seed in split precision. Slot 6 holds half the variance. #}
 {{ ptr('LR11',12) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ ve(first=true) }}
 {{ save(12) }}
 SET LR12 CR0 ;;
 INC LR12 4 ;;
refine:
 {{ product(12,12) }}
 {{ save(16) }}
 {{ product(8,16) }}
 {{ save(20) }}
 {{ accumulate_parts(12,cr.tmp,first=true,count=4) }}
 {{ product(12,8,cr.stats,other=1,first=false) }}
 {# Keep the Newton subtraction in the accumulator: 1.5*y - 0.5*v*y^3. #}
 {{ product(12,20,first=false,op='SUB') }}
 {{ save(12) }}
 DEC LR12 1 ; BNE LR12 CR0 refine ;;

 {{ reset() }}
 SET LR7 CR0 ;;
output:
 {{ product(12,'LR6') }}
 {{ save(24) }}
 {{ product(24,'LR7',cr.affine,other=4) }}
 INC LR11 1 ;;
 {{ accumulate_parts('LR11',cr.affine,count=4) }}
 SET LR7 LR11 ;;
 BEQ LR3 LR8 output_tail ;;
 {{ store(full) }}
 B output_next ;;
output_tail:
 {{ store(tail) }}
output_next:
 INC LR6 4 ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 output ;;
 BEQ LR3 LR8 next_batch ;;
 INC LR3 1 ; INC LR2 1 ;;
 B tile ;;
next_batch:
 SUB LR2 LR4 LR8 ; SET LR3 CR1 ;;
 INC LR2 1 ;;
 BLT.S LR2 LR9 tile ;;
 HALT ;;
