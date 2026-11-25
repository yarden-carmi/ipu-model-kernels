{% set q = cr.qf_in0 ~ '.L' %}
{% set iq = cr.qf_in1 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro init(reg, n=0) %}
 SET {{ reg }} CR0 ;;
 {% if n %} INC {{ reg }} {{ n }} ;; {% endif %}
{% endmacro %}
{% macro vec(op='ADD', first=false, imm='CR1', fmt=q, agg='') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; {% if agg %}AGG.SUM LR0 {{ agg }}{% else %}ACC.{{ op }}{% if first %}.FIRST{% endif %}{% endif %} ;;
{% endmacro %}
{% macro load(n, cyclic=false, base=cr.tmp) %}
 {{ init('LR1',n) }}
 {% if cyclic %}LD.MULT.CYCLIC LR1 {{ base }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ base }} ;;{% endif %}
{% endmacro %}
{% macro mul(first=false, slot='LR0', agg='') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; {% if agg %}AGG.SUM LR0 {{ agg }}{% else %}ACC.ADD{% if first %}.FIRST{% endif %}{% endif %} ;;
{% endmacro %}
{% macro split(reg, count, fmt=q) %}
 {% for p in range(count) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ fmt }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ vec('SUB',fmt=fmt) }}
 INC {{ reg }} 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n, count=2, fmt=q) %}{{ init('LR1',n) }}{{ split('LR1',count,fmt) }}{% endmacro %}
{% macro average() %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j,true,cr.coeff) }}
 {% for i in range(3) %}{{ load(i) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,na,b,nb) %}
 {% for i in range(na) %}
 {{ load(a+i,true) }}
 {% for j in range(nb) %}{{ load(b+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 {% endfor %}
{% endmacro %}
{% macro weight(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro dot(src, first=false) %}
 {% for p in range(3) %}
 MULT.RC.VE {{ 'LR3' if p % 2 else 'LR0' }} {{ src }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first and p == 0 %}.FIRST{% endif %}
 {% if p < 2 %}; {{ weight('LR0' if p % 2 else 'LR3') }}{% elif not first %}; BNE LR7 CR0 feature{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro raw_reduce(ds, square=false) %}
 {% if square %}
 {% for a,b in [(0,0),(0,1),(1,1)] %}
 {% if a == b %}LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;{% endif %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for j in range(2 if a != b else 1) %}{{ mul(agg=ds) }}{% endfor %}
 {% if a == b %}INC LR9 1 ;;{% endif %}
 {% endfor %}
 {% else %}
 {% for p in range(2) %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ vec(agg=ds) }}
 INC LR9 1 ;;
 {% endfor %}
 {% endif %}
{% endmacro %}
{% macro reduce(label, square=false) %}
 {{ vec(first=true,imm='CR0') }}
 {{ init('LR9',24) }}
 SET LR6 {{ cr.tiles }} ;;
 {{ label }}:
 DEC LR6 1 ;;
 BEQ LR6 CR0 {{ label }}_tail ;;
 {{ raw_reduce(full,square) }}
 B {{ label }} ;;
 {{ label }}_tail:
 {{ raw_reduce(tail,square) }}
 {{ average() }}
{% endmacro %}

 SET LR0 CR0 ; SET LR5 CR0 ; SET LR11 CR0 ;;
 SET LR13 CR0 ; SET LR15 CR0 ;;
row:
 SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR10 LR15 ;;
 DEC LR4 1 ;;
 {{ init('LR9',24) }}
tile:
 {# Gather the residual's channel vector from its row-lane layout. #}
 SET LR1 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 {{ vec(first=true,imm='CR0',fmt=iq) }}
 DEC LR6 1 ;;
 SET LR7 LR8 ; BEQ LR6 CR0 gather ;;
 {{ init('LR7',128) }}
gather:
 LD.MULT R0 LR10 {{ cr.in1 }} ; DEC LR7 1 ;;
 MULT.EE LR13 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR10 LR10 {{ cr.blocks }} ;;
 ADDBI LRD2 1 ; BNE LR7 CR0 gather ;;
 {{ save(20,3,iq) }}

 {{ init('LR3',128) }}
 SET LR2 LR11 ; SET LR7 LR12 ;;
 {{ weight('LR0') }} ;;
 {{ dot('CR1',true) }}
feature:
 LD.MULT R0 LR2 {{ cr.in0 }} ; DEC LR7 1 ;;
 {{ weight('LR0') }} ; ADD LR2 LR2 {{ cr.blocks }} ;;
 {{ dot('LR13') }}
 {% for p in range(3) %}{{ load(20+p) }}{{ vec(fmt=iq) }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ; BNE LR6 CR0 tile ;;

 {{ reduce('sum') }}
 {{ save(6,3) }}
 {{ init('LR9',24) }}
 SET LR6 {{ cr.tiles }} ;;
center:
 SET LR10 LR9 ;;
 {% for p in range(2) %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ vec(first=loop.first) }}
 INC LR9 1 ;;
 {% endfor %}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR10',2) }}
 DEC LR6 1 ; BNE LR6 CR0 center ;;

 {{ reduce('variance',true) }}
 {{ load(3,base=cr.coeff) }}{{ vec() }}
 {{ init('LR1',12) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(9,3) }}
 {{ init('LR1',13) }}{{ vec(first=true,imm='CR0') }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ init('LR4',2) }}
refine:
 {{ product(12,2,12,2) }}{{ save(14) }}
 {{ product(9,3,14,2) }}{{ save(16) }}
 {{ product(12,2,16,2) }}{{ save(18) }}
 {% for i in range(2) %}
 {{ load(12+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [18,19] %}{{ load(n) }}{{ vec('SUB',imm=cr.half) }}{% endfor %}
 {{ save(12) }}
 DEC LR4 1 ; BNE LR4 CR0 refine ;;

 {{ init('LR9',24) }}
 {{ init('LR10',4) }}
 SET LR6 {{ cr.tiles }} ;;
normalize:
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ; INC LR9 1 ;;
 INC LR9 1 ;;
 {% for n in [12,13] %}{{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 {{ save(20) }}
 {% for i in range(3) %}
 LD.MULT.CYCLIC LR10 {{ cr.coeff }} LR0 ;;
 {% for j in range(2) %}{{ load(20+j) }}{{ mul(first=(i==0 and j==0)) }}{% endfor %}
 INC LR10 1 ;;
 {% endfor %}
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.coeff }} ;;
 {{ vec() }}
 INC LR10 1 ;;
 {% endfor %}
 DEC LR6 1 ;;
 BEQ LR6 CR0 store_tail ;;
 {% macro output(ds) %}ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;; INC LR5 1 ;;{% endmacro %}
 {{ output(full) }}
 B normalize ;;
store_tail:
 {{ output(tail) }}
 DEC LR14 1 ;;
 BEQ LR14 CR0 finish ;;
 INC.MODP2 LR13 CR1 7 ;;
 BNE LR13 CR0 row ;;
 INC LR11 1 ; INC LR15 1 ; B row ;;
finish:
 HALT ;;
