{% set q = cr.qf_in0 ~ '.L' %}
{% set ds = 'CR15.L' %}
{% macro at(r,n) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro ve(op='ADD',first=false,k='CR1',fmt=q) %}
 MULT.VE LR0 {{ k }} 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro vv(op='ADD',first=false,slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n,base=cr.tmp,slot=none) %}
 {{ at('LR1',n) }}
 {% if slot is none %}LD.MULT R0 LR1 {{ base }} ;;
 {% else %}LD.MULT.CYCLIC LR1 {{ base }} {{ slot }} ;;{% endif %}
{% endmacro %}
{% macro encode(r,parts) %}
 {% for j in range(parts) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ r }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ r }} {{ cr.tmp }} ;;
 {{ ve('SUB') }}
 INC {{ r }} 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,parts=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',parts) }}
{% endmacro %}
{% macro average(src,dest,parts,eps=false) %}
 {{ save(src,3) }}
 {% for i in range(3) %}
 {{ load(src+i) }}
 MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(src,3) }}
 {% for i in range(3) %}
 {{ load(src+i,slot='LR0') }}
 {{ at('LR1',0) }}
 {% for j in range(3) %}
 LD.MULT R0 LR1 {{ cr.scale }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if i==0 and j==0 %}.FIRST{% endif %} ; INC LR1 1 ;;
 {% endfor %}
 {% endfor %}
 {% if eps %}
 {{ load(3,cr.scale) }}{{ ve() }}
 {{ at('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ q }} {{ cr.tmp }} LR1 ;;
 {% endif %}
 {{ save(dest,parts) }}
{% endmacro %}
{% macro product(a,na,b,nb) %}
 {% for i in range(na) %}
 {{ load(a+i,slot='LR0') }}
 {{ at('LR1',b) }}
 {% for j in range(nb) %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if i==0 and j==0 %}.FIRST{% endif %} ; INC LR1 1 ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro refine(r,n,dest) %}
 {# Compute r²v, then r + r(1-r²v)/2. #}
 {{ product(r,n,r,n) }}{{ save(16) }}
 {{ product(16,2,9,2) }}{{ save(18) }}
 {{ load(r) }}{{ ve(first=true,k=cr.half) }}
 {% for i in range(1,n) %}{{ load(r+i) }}{{ ve(k=cr.half) }}{% endfor %}
 {{ save(20) }}
 {{ product(20,2,18,2) }}{{ save(22) }}
 {% for i in range(n) %}
 {{ load(r+i) }}{{ ve(first=(i==0)) }}{{ ve(k=cr.half) }}
 {% endfor %}
 {% for i in range(2) %}{{ load(22+i) }}{{ ve('SUB') }}{% endfor %}
 {{ save(dest) }}
{% endmacro %}
{% macro start() %}
 {{ at('LR5',24) }}
 ADD LR12 LR5 {{ cr.chunks }} ;;
{% endmacro %}
{% macro step(label) %}
 INC LR5 1 ;;
 BLT.S LR5 LR12 {{ label }} ;;
{% endmacro %}
{% macro store(d) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ d }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR15 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR13 CR0 ;;
 SET LR14 CR0 ; SET LR15 CR0 ; SET LR7 CR0 ;;
row:
 {{ start() }}
 SET LR3 LR2 ; ADD LR4 LR2 {{ cr.batch_stride }} ; SET LR1 CR0 ;;
gather_chunk:
 {{ ve(first=true,k='CR0') }}
 SET LR10 CR0 ; SET LR11 CR0 ; SET LR6 CR0 ;;
 INC LR6 128 ;;
gather_channel:
 LD.MULT R0 LR3 {{ cr.in0 }} ;;
 MULT.EE LR7 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.RESHAPE LRD0 LRD10 7 ; ADD LR3 LR3 {{ cr.tiles }} ; DEC LR6 1 ;;
 BGE.S LR3 LR4 gather_store ;;
 ADDBI LRD10 1 ;;
 BLT.S CR0 LR6 gather_channel ;;
gather_store:
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR5 ;;
 {{ step('gather_chunk') }}

 {{ start() }}{{ ve(first=true,k='CR0') }}
sum:
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {{ step('sum') }}
 {{ average(0,3,3) }}

 {{ start() }}
 SET LR6 LR12 ;;
center:
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ ve(first=true) }}
 {% for j in range(3,6) %}{{ load(j) }}{{ ve('SUB') }}{% endfor %}
 ADD LR10 LR5 CR1 ;;
 BNE LR10 LR12 center_store ;;
 ACTIVATE.QUANTIZE identity CR14.L {{ q }} {{ cr.tmp }} LR6 ;;
 LD.MULT R0 LR6 {{ cr.tmp }} ;;
 {{ ve('SUB') }}
 INC LR6 1 ;;
 ACTIVATE.QUANTIZE identity CR14.L {{ q }} {{ cr.tmp }} LR6 ;;
 BEQ CR0 CR0 variance_start ;;
center_store:
 {{ encode('LR6',2) }}
 INC LR6 1 ; INC LR5 1 ;;
 BEQ CR0 CR0 center ;;

variance_start:
 ADD LR4 LR6 CR1 ; SET LR5 LR12 ;;
 {{ ve(first=true,k='CR0') }}
variance:
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR5 1 ;;
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR5 1 ;;
 BLT.S LR5 LR4 variance ;;
 {{ average(6,9,2,true) }}
 {{ refine(12,1,13) }}{{ refine(13,2,12) }}

 SET LR5 LR12 ; SET LR6 CR0 ;;
 {{ at('LR11',128) }}
output:
 {% for i in range(2) %}
 {{ load(12+i,slot=['LR0','LR11'][i]) }}
 {% endfor %}
 {% for j in range(3) %}
 LD.MULT R0 LR6 {{ cr.affine }} ;;
 {{ vv(first=(j==0)) }}{{ vv(slot='LR11') }}
 INC LR6 1 ;;
 {% endfor %}
 {{ save(16) }}
 {% for slot in ['LR0','LR11'] %}
 LD.MULT.CYCLIC LR5 {{ cr.tmp }} {{ slot }} ;;
 INC LR5 1 ;;
 {% endfor %}
 {% for j in range(16,18) %}
 {{ load(j) }}{{ vv(first=(j==16)) }}{{ vv(slot='LR11') }}
 {% endfor %}
 {% for j in range(3) %}
 LD.MULT R0 LR6 {{ cr.affine }} ;;
 {{ ve(fmt=cr.qf_affine ~ '.L') }}
 INC LR6 1 ;;
 {% endfor %}
 BGE.S LR5 LR4 last_store ;;
 {{ store(ds) }}
 INC LR15 1 ; BEQ CR0 CR0 output ;;
last_store:
 {{ store('CR14.L') }}
 INC LR15 1 ; INC LR7 1 ; INC LR14 1 ;;
 BGE.S LR14 LR9 next_batch ;;
 {{ at('LR6',128) }}
 BLT.S LR7 LR6 row ;;
 SET LR7 CR0 ; INC LR2 1 ; BEQ CR0 CR0 row ;;
next_batch:
 ADD LR2 LR2 {{ cr.batch_stride }} ;;
 SUB LR2 LR2 {{ cr.tiles }} ;;
 INC LR2 1 ; SET LR7 CR0 ; SET LR14 CR0 ;;
 INC LR13 1 ;;
 BLT.S LR13 LR8 row ;;
 HALT ;;
