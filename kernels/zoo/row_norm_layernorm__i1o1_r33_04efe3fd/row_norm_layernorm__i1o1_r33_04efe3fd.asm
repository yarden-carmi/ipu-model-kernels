{% set q = cr.qf_stats ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set aq = cr.qf_affine ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set parts = 8 %}
{% macro ptr(r,n) %}
 SET {{ r }} {% if n is number %}CR0{% else %}{{ n }}{% endif %} ;;
 {% if n is number and n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,fmt=q,scalar='CR1') %}
 MULT.VE LR0 {{ scalar }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro save(n) %}
 {{ ptr('LR10',n) }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {% for i in range(parts-1) %}
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR10 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR10 ;;
 {% endfor %}
{% endmacro %}
{% macro product(label,a,b,base=cr.tmp,first=true,fmt=q) %}
 {{ ptr('LR10',a) }}
 {{ ptr('LR13',parts) }}
 {% if first %}{{ vec(first=true,scalar='CR0',fmt=fmt) }}{% endif %}
{{ label }}_part:
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
 {{ ptr('LR11',b) }}
 LD.MULT R0 LR11 {{ base }} ;;
 {% for i in range(parts) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ fmt }} ; ACC.ADD{% if not loop.last %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ base }}{% else %} ; INC LR10 1 ; DEC LR13 1{% endif %} ;;
 {% endfor %}
 BNE LR13 CR0 {{ label }}_part ;;
{% endmacro %}
{% macro accum(n,base,op='ADD',fmt=q) %}
 {{ ptr('LR11',n) }}
 {% for i in range(parts) %}
 LD.MULT R0 LR11 {{ base }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }} ; INC LR11 1 ;;
 {% endfor %}
{% endmacro %}
{% macro average(label) %}
 {{ save(0) }}
 {{ product(label,0,0,cr.stats) }}
{% endmacro %}
{% macro reset() %}
 SET LR4 LR2 ; SET LR5 {{ cr.channels }} ;;
 {{ ptr('LR6',8*parts) }}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR1 ;;
tile:
 {# A lane carries one token throughout; adjacent channels are stride words apart. #}
 {{ reset() }}
 {{ vec(first=true,scalar='CR0') }}
sum:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.ADD ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 sum ;;
 {{ average('mean') }}
 {{ save(parts) }}

 {{ reset() }}
center:
 LD.MULT R0 LR4 {{ cr.in0 }} ;;
 {{ vec(first=true,fmt=iq) }}
 {{ accum(parts,cr.tmp,'SUB') }}
 {{ save('LR6') }}
 INC LR6 {{ parts }} ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 center ;;

 {{ reset() }}
 SET LR14 LR6 ;;
 {% for _ in range(parts) %}ADD LR14 LR14 {{ cr.channels }} ;;{% endfor %}
 SET LR15 LR14 ;;
variance_block:
 {{ ptr('LR12',8) }}
 {{ vec(first=true,scalar='CR0') }}
variance:
 {{ product('square','LR6','LR6',first=false) }}
 INC LR6 {{ parts }} ; DEC LR5 1 ; DEC LR12 1 ;;
 BEQ LR5 CR0 variance_save ;;
 BNE LR12 CR0 variance ;;
variance_save:
 {{ save('LR15') }}
 INC LR15 {{ parts }} ;;
 BNE LR5 CR0 variance_block ;;
 {{ vec(first=true,scalar='CR0') }}
variance_reduce:
 LD.MULT R0 LR14 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; INC LR14 1 ;;
 BNE LR14 LR15 variance_reduce ;;
 {{ average('mean_square') }}
 {{ accum(parts,cr.stats) }}
 {{ ptr('LR11',3*parts) }}
 BEQ LR3 LR8 seed_tail ;;
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR11 ;;
 B seed_done ;;
seed_tail:
 ACTIVATE.QUANTIZE rsqrt {{ tail }} {{ q }} {{ cr.tmp }} LR11 ;;
seed_done:
 {{ save(2*parts) }}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 {{ vec(first=true) }}
 {{ save(3*parts) }}

 {# Newton refinement, multiplying v by y first for mixed-scale tiles. #}
 {{ ptr('LR12',8) }}
refine:
 {{ product('vy',2*parts,3*parts) }}
 {{ save(4*parts) }}
 {{ product('vyy',4*parts,3*parts) }}
 {{ save(5*parts) }}
 {{ ptr('LR11',2*parts) }}
 LD.MULT R0 LR11 {{ cr.stats }} ;;
 {{ vec(first=true) }}
 INC LR11 1 ; LD.MULT.CYCLIC LR11 {{ cr.stats }} LR0 ;;
 {{ ptr('LR11',5*parts) }}
 {% for i in range(parts) %}
 LD.MULT R0 LR11 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR11 1 ;;
 {% endfor %}
 {{ save(6*parts) }}
 {{ product('correct',6*parts,3*parts) }}
 {{ save(3*parts) }}
 DEC LR12 1 ;;
 BNE LR12 CR0 refine ;;

 {{ reset() }}
 SET LR7 CR0 ;;
output:
 {{ product('normalize',3*parts,'LR6') }}
 {{ save(4*parts) }}
 {{ product('scale',4*parts,'LR7',cr.affine,fmt=aq) }}
 INC LR7 {{ parts }} ;;
 {{ accum('LR7',cr.affine,fmt=aq) }}
 SET LR7 LR11 ;;
 BEQ LR3 LR8 output_tail ;;
 {{ store(full) }}
 B output_next ;;
output_tail:
 {{ store(tail) }}
output_next:
 INC LR6 {{ parts }} ; ADD LR4 LR4 LR8 ; DEC LR5 1 ;;
 BNE LR5 CR0 output ;;
 BEQ LR3 LR8 next_batch ;;
 INC LR3 1 ; INC LR2 1 ;;
 B tile ;;
next_batch:
 SUB LR2 LR4 LR8 ; SET LR3 CR1 ;;
 INC LR2 1 ;;
 BLT.S LR2 LR9 tile ;;
 HALT ;;
