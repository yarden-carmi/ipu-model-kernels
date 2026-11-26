{% set f = cr.full ~ '.L' %}
{% set t = cr.tail ~ '.L' %}
{% set q = cr.qf_coeff ~ '.L' %}
{% macro at(r,n=0) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op,fmt=q,s='CR1') %}
 MULT.VE LR0 {{ s }} 0 LR0 {{ f }} {{ fmt }} ; ACC.{{ op }} ;;
{% endmacro %}
{% macro ld(p,base=cr.tmp,slot='') %}
 {% if slot %}LD.MULT.CYCLIC {{ p }} {{ base }} {{ slot }} ;;
 {% else %}LD.MULT R0 {{ p }} {{ base }} ;;{% endif %}
{% endmacro %}
{% macro load(n,slot='',base=cr.tmp) %}
 {{ at('LR1',n) }}{{ ld('LR1',base,slot) }}
{% endmacro %}
{% macro mul(op='ADD',slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ f }} {{ q }} ; ACC.{{ op }} ;;
{% endmacro %}
{% macro split(p,count,ds=f) %}
 {% for i in range(count) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ p }} ;;
 {% if not loop.last %}{{ ld(p) }}{{ vec('SUB') }}{% endif %}
 INC {{ p }} 1 ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=2) %}{{ at('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro product(a,b,na,nb) %}
 {% for i in range(na) %}
 {{ load(a+i,'LR0') }}
 {% for j in range(nb) %}{{ load(b+j) }}{{ mul('ADD.FIRST' if i == 0 and j == 0 else 'ADD') }}{% endfor %}
 {% endfor %}
{% endmacro %}
{% macro add_inputs() %}
 {{ ld('LR5',cr.in0) }}{{ vec('ADD.FIRST',cr.qf_in0 ~ '.L') }}
 {{ ld('LR5',cr.in1) }}{{ vec('ADD',cr.qf_in1 ~ '.L') }}
{% endmacro %}
{% macro reduce_inputs(ds) %}
 {% for src in ['in0','in1'] %}
 {{ ld('LR5',cr[src]) }}
 MULT.VE LR0 CR1 0 LR0 {{ f }} {{ cr['qf_' ~ src] }}.L ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
{% endmacro %}
{% macro squares(ds) %}
 {{ ld('LR9',cr.tmp,'LR0') }}{{ ld('LR9') }}
 MULT.RC.VV LR0 R0 0 LR0 {{ f }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
 {{ ld('LR9') }}
 {% for _ in range(2) %}MULT.RC.VV LR0 R0 0 LR0 {{ f }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;{% endfor %}
 {{ ld('LR9',cr.tmp,'LR0') }}
 MULT.RC.VV LR0 R0 0 LR0 {{ f }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
{% endmacro %}
{% macro broadcast_sum() %}
 {{ save(0,3) }}
 {% for i in range(3) %}
 {{ load(i) }}
 MULT.EE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR8 CR0 ; SET LR15 {{ cr.s1_rows }} ;;
 INC LR8 128 ;;
row:
 SET LR5 LR2 ; SET LR6 CR1 ;;
 {{ vec('ADD.FIRST',q,'CR0') }}
 BGE.S LR6 {{ cr.chunks }} sum_tail ;;
sum_full:
 {{ reduce_inputs(f) }}
 INC LR5 1 ; INC LR6 1 ;;
 BLT.S LR6 {{ cr.chunks }} sum_full ;;
sum_tail:
 {{ reduce_inputs(t) }}
 {{ broadcast_sum() }}{{ save(3,3) }}
 {{ vec('ADD.FIRST',q,'CR0') }}
 {{ at('LR10') }}{{ at('LR7',3) }}
mean:
 {{ ld('LR10',cr.coeff,'LR0') }}
 {% for n in range(3,6) %}{{ load(n) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 mean ;;
 {{ save(6,3) }}

 SET LR5 LR2 ; SET LR6 {{ cr.chunks }} ;;
 {{ at('LR9',32) }}
center:
 {{ add_inputs() }}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR5 1 ; DEC LR6 1 ;;
 BNE LR6 CR0 center ;;
 SET LR2 LR5 ; SET LR6 CR1 ;;
 {{ vec('ADD.FIRST',q,'CR0') }}
 {{ at('LR9',32) }}
 BGE.S LR6 {{ cr.chunks }} variance_tail ;;
variance:
 {{ squares(f) }}
 INC LR6 1 ;;
 BLT.S LR6 {{ cr.chunks }} variance ;;
variance_tail:
 {{ squares(t) }}
 {{ broadcast_sum() }}
 {{ load(3,base=cr.coeff) }}{{ vec('ADD') }}
 {{ at('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ f }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ at('LR1',13) }}{{ vec('ADD.FIRST',q,'CR0') }}
 ACTIVATE.QUANTIZE identity {{ f }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ at('LR4',2) }}
refine:
 {{ product(12,12,2,2) }}{{ save(14) }}
 {{ product(9,14,3,2) }}{{ save(16) }}
 {{ product(12,16,2,2) }}{{ save(18) }}
 {% for i in range(2) %}
 {{ load(12+i) }}{{ vec('ADD.FIRST' if loop.first else 'ADD') }}{{ vec('ADD',q,cr.half) }}
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',q,cr.half) }}{% endfor %}
 {{ save(12) }}
 DEC LR4 1 ;;
 BNE LR4 CR0 refine ;;

 SET LR6 {{ cr.chunks }} ;;
 {{ at('LR9',32) }}{{ at('LR7',3) }}{{ at('LR10',4) }}
normalize:
 SET LR4 CR0 ;;
 {{ vec('ADD.FIRST',q,'CR0') }}
weight:
 {{ ld('LR10',cr.coeff,'LR0') }}
 {% for n in [12,13] %}{{ load(n) }}{{ mul() }}{% endfor %}
 INC LR10 1 ; INC LR4 1 ;;
 BLT.S LR4 LR7 weight ;;
 {{ save(20,3) }}
 {% for slot in ['LR0','LR8'] %}{{ ld('LR9',cr.tmp,slot) }} INC LR9 1 ;;{% endfor %}
 {% for n in range(20,23) %}{{ load(n) }}{{ mul('ADD.FIRST' if loop.first else 'ADD') }}{{ mul(slot='LR8') }}{% endfor %}
 {% for i in range(3) %}{{ ld('LR10',cr.coeff) }}{{ vec('ADD') }} INC LR10 1 ;;{% endfor %}
 DEC LR6 1 ;;
 BEQ LR6 CR0 last_output ;;
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ f }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ; B normalize ;;
last_output:
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ t }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
 INC LR3 1 ; DEC LR15 1 ;;
 BNE LR15 CR0 row ;;
 HALT ;;
