{% set q = cr.work ~ '.H' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.work ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(r,n=0) %}
 SET {{ r }} CR0 ;;
 {% if n %}INC {{ r }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,fmt=q,s='CR1',lane='LR0') %}
 MULT.VE {{ lane }} {{ s }} 0 {{ lane }} {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro load(n,cyclic=false) %}
 {{ at('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro mul(first=false,slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro split(reg,count,base=cr.tmp,step='') %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ base }} {{ reg }} ;;
 {% for p in range(count-1) %}
 LD.MULT R0 {{ reg }} {{ base }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; {% if step %}ADD {{ reg }} {{ reg }} {{ step }}{% else %}INC {{ reg }} 1{% endif %} ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ base }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,count=2) %}{{ at('LR1',n) }}{{ split('LR1',count) }}{% endmacro %}
{% macro average(label) %}
 {{ save(0,3) }}
 {% for p in range(3) %}
 {{ load(p) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 SET LR10 CR0 ; SET LR7 CR0 ;;
 INC LR7 3 ;
 MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for p in range(3,6) %}{{ load(p) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro squares(ds) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for _ in range(2) %}MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;{% endfor %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
{% endmacro %}
{% macro product(a,b,na,nb) %}
 {% for i in range(na) %}
 {{ load(a+i,true) }}
 {% for j in range(nb) %}{{ load(b+j) }}{{ mul(i==0 and j==0) }}{% endfor %}
 {% endfor %}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ;;
row:
 SET LR5 LR2 ; ADD LR6 LR2 {{ cr.K }} ;;
 {{ vec(first=true,s='CR0') }}
sum:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR6 sum ;;
 {{ average('mean') }}{{ save(6,3) }}

 SET LR5 LR2 ;
 {{ at('LR9',32) }}
center:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ vec(first=true,fmt=iq) }}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ;;
 BLT.S LR5 LR6 center ;;

 {{ vec(first=true,s='CR0') }}
 {{ at('LR9',32) }}
 ADD LR5 LR2 CR1 ;;
 BGE.S LR5 LR6 variance_tail ;;
variance:
 {{ squares(full) }}
 INC LR5 1 ;;
 BLT.S LR5 LR6 variance ;;
variance_tail:
 {{ squares(tail) }}
 {{ average('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec() }}
 {{ at('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ at('LR1',13) }}{{ vec(first=true,s='CR0') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {# Newton refinement of y = rsqrt(v): y <- y * (1.5 - 0.5*v*y*y). #}
 {{ at('LR4',2) }}
refine:
 {{ product(12,12,2,2) }}{{ save(14) }}
 {{ product(9,14,3,2) }}{{ save(16) }}
 {{ product(12,16,2,2) }}{{ save(18) }}
 {% for i in range(2) %}
 {{ load(12+i) }}
 {{ vec(first=loop.first) }}{{ vec(s=cr.half) }}
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',s=cr.half) }}{% endfor %}
 {{ save(12) }}
 DEC LR4 1 ;;
 BNE LR4 CR0 refine ;;

 SET LR5 LR2 ; SET LR11 CR0 ;
 {{ at('LR9',32) }}{{ at('LR7',3) }}
normalize:
 SET LR10 LR11 ; SET LR4 CR0 ;;
 {{ vec(first=true,s='CR0') }}
weight:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in [12,13] %}{{ load(n) }}{{ mul() }}{% endfor %}
 ADD LR10 LR10 {{ cr.K }} ; INC LR4 1 ;;
 BLT.S LR4 LR7 weight ;;
 {{ save(20,3) }}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR9 1 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 INC LR9 1 ;;
 {% for n in range(20,23) %}{{ load(n) }}{{ mul(loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ADD LR10 LR10 {{ cr.K }} ;;
 {% endfor %}
 SET LR8 LR5 ;;
 {{ split('LR8',3,cr.normalized,'LR13') }}
 INC LR5 1 ; INC LR11 1 ;;
 BLT.S LR5 LR6 normalize ;;
 SET LR2 LR6 ;;
 BLT.S LR2 LR13 row ;;

 {# Gather channels across token tiles, reconstructing residuals before
    the final store in the consumer's layout and format. #}
{% macro scatter() %}
 MULT.EE LR4 CR1 0 LR15 {{ full }} {{ q }} ; ACC.RESHAPE LRD14 LRD10 7 ;
{% endmacro %}
{% macro gather(p) %}
 SET LR6 LR2 ; SET LR8 CR1 ; SET LR11 CR0 ;;
 {% for i in range(p) %}ADD LR6 LR6 LR13 ;;{% endfor %}
 {% if p == 2 %}
 BGE.S LR7 LR3 gather{{ p }} ;;
 {{ vec(first=true,s='CR0',lane='LR15') }}
 {% endif %}
gather{{ p }}:
 INC LR8 1 ; LD.MULT R0 LR6 {{ cr.normalized }} ;;
 {{ scatter() }} ADD LR6 LR6 {{ cr.K }} ; BGE.S CR1 LR7 gathered{{ p }} ;;
 LD.MULT R0 LR6 {{ cr.normalized }} ;;
gather_pipe{{ p }}:
 {{ scatter() }} ADDBI LRD10 1 ; ADD LR6 LR6 {{ cr.K }} ; INC LR8 1 ; LD.MULT R0 LR6 {{ cr.normalized }} ; BLT.S LR8 LR7 gather_pipe{{ p }} ;;
gathered{{ p }}:
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
 SET LR2 CR0 ; SET LR15 CR0 ;;
batch:
 SET LR4 CR0 ; SET LR1 LR2 ; SET LR9 CR0 ;;
channel:
 SET LR2 LR1 ; SET LR5 LR12 ;;
tile:
 SET LR7 LR3 ; SET LR10 CR0 ; BGE.S LR5 LR3 tile_ready ;;
 SET LR7 LR5 ;;
tile_ready:
 {% for p in [2,1,0] %}
 {{ gather(p) }}
 {% if not loop.first %}
 {% for r in range(2 if p == 0 else 1) %}
 {{ at('LR8',r) }}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 {{ vec(lane='LR15') }}
 {% endfor %}
 {% endif %}
 {% if not loop.last %}
 {{ at('LR8') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% if p == 1 %}
 LD.MULT R0 LR8 {{ cr.tmp }} ;;
 MULT.VE LR15 CR1 0 LR15 {{ full }} {{ q }} ; ACC.SUB ; INC LR8 1 ;;
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR8 ;;
 {% endif %}
 {% endif %}
 {% endfor %}
 BLT.S LR7 LR3 store_tail ;;
 {{ store(full) }}
 B advance ;;
store_tail:
 {{ store(cr.tail ~ '.H') }}
advance:
 INC LR0 1 ; SUB LR5 LR5 LR7 ; SET LR2 LR6 ;;
 BLT.S CR0 LR5 tile ;;
 INC LR9 1 ; INC.MODP2 LR4 CR1 7 ;;
 BNE LR4 CR0 same_chunk ;;
 INC LR1 1 ;;
same_chunk:
 BLT.S LR9 LR14 channel ;;
 SUB LR2 LR6 {{ cr.K }} ;;
 INC LR2 1 ;;
 BLT.S LR2 LR13 batch ;;
 HALT ;;
