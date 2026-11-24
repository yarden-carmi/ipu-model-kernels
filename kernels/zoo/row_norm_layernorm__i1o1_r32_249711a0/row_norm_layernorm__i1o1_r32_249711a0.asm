{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = 'CR15.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro vec(op='ADD',first=false,imm='CR1') %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro mul(first=false,slot='LR0') %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %} ;;
{% endmacro %}
{% macro clear() %}{{ vec(first=true,imm='CR0') }}{% endmacro %}
{% macro split(reg,pieces) %}
 {% for i in range(pieces) %}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% if not loop.last %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ vec('SUB') }}
 INC {{ reg }} 1 ;;
 {% endif %}
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ split('LR1',pieces) }}
{% endmacro %}
{% macro mean(label) %}
 {{ save(0,3) }}
 {% for i in range(3) %}
 {{ load(i) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ clear() }}
 SET LR10 CR0 ;;
{{ label }}:
 LD.MULT.CYCLIC LR10 {{ cr.crow }} LR0 ;;
 {% for i in range(3,6) %}{{ load(i) }}{{ mul() }}{% endfor %}
 INC LR10 1 ;;
 BLT.S LR10 LR7 {{ label }} ;;
{% endmacro %}
{% macro square_sum(ds) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
 {% endfor %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR9 1 ;;
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}
 {% for j in range(2) %}{{ load(b+j) }}{{ mul(first=i==0 and j==0) }}{% endfor %}
 {% endfor %}
 {{ save(dest) }}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
 {{ at('LR3',128) }}{{ at('LR7',3) }}
row_loop:
 {# Select lane zero of each stored channel row, then split the gathered
    vector so that reblocking does not discard low-order input bits. #}
 SET LR5 LR4 ; ADD LR6 LR4 LR15 ;;
 {{ at('LR9',32) }}
gather_tile:
 SET LR1 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
 {{ at('LR8',128) }}
 {{ clear() }}
gather_lane:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD10 7 ; DEC LR8 1 ; INC LR5 {{ (in0_d1 + 127) // 128 }} ;;
 ADDBI LRD10 1 ;;
 BGE.S LR5 LR6 gather_end ;;
 BNE LR8 CR0 gather_lane ;;
gather_end:
 {{ split('LR9',2) }}
 INC LR9 1 ;;
 BLT.S LR5 LR6 gather_tile ;;

 {{ at('LR5',32) }}
 {{ clear() }}
sum_loop:
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ;;
 BLT.S LR5 LR14 sum_loop ;;
 {{ mean('mean_scale') }}{{ save(6,3) }}

 {{ at('LR5',32) }}
 SET LR9 LR14 ;;
center_loop:
 {% for i in range(2) %}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ vec(first=loop.first) }}
 INC LR5 1 ;;
 {% endfor %}
 {% for n in range(6,9) %}{{ load(n) }}{{ vec('SUB') }}{% endfor %}
 {{ split('LR9',2) }}
 INC LR9 1 ;;
 BLT.S LR5 LR14 center_loop ;;

 {{ clear() }}
 {{ at('LR5',1) }}
 SET LR9 LR14 ;;
 BLT.S LR5 {{ cr.K }} variance_full ;;
 BLT.S CR0 CR1 variance_tail ;;
variance_full:
 {{ square_sum(full) }}
 INC LR5 1 ;;
 BLT.S LR5 {{ cr.K }} variance_full ;;
variance_tail:
 {{ square_sum(tail) }}
 {{ mean('variance_scale') }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ vec() }}

 {# Refine a quantized rsqrt seed twice with Newton's iteration. #}
 {{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ vec('SUB') }}{{ save(22,1) }}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {% for src,count,dst in [(8,1,19),(19,2,23)] %}
 {{ clear() }}
 {% for n in [11,12,22] %}
 {{ load(n,true) }}{{ load(13) }}{{ mul() }}{{ load(14) }}{{ mul() }}
 {% endfor %}
 {{ save(15) }}
 {{ clear() }}
 {% for i in range(count) %}
 {{ load(src+i,true) }}{{ load(15) }}{{ mul() }}{{ load(16) }}{{ mul() }}
 {% endfor %}
 {{ save(17) }}
 {% for i in range(count) %}
 {{ load(src+i,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ vec('SUB',imm=cr.half) }}{% endfor %}
 {{ save(dst) }}
 {% if not loop.last %}{{ product(dst,dst,13) }}{% endif %}
 {% endfor %}

 SET LR11 CR0 ; SET LR9 LR14 ;;
output_loop:
 SET LR10 LR11 ; SET LR5 CR0 ;;
 {{ clear() }}
weight_loop:
 LD.MULT.CYCLIC LR10 {{ cr.gamma }} LR0 ;;
 {% for n in [23,24] %}{{ load(n) }}{{ mul() }}{% endfor %}
 ADD LR10 LR10 {{ cr.K }} ; INC LR5 1 ;;
 BLT.S LR5 LR7 weight_loop ;;
 {{ save(9,3) }}
 {% for slot in ['LR0','LR3'] %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} {{ slot }} ;;
 INC LR9 1 ;;
 {% endfor %}
 {% for n in [9,10,11] %}{{ load(n) }}{{ mul(first=loop.first) }}{{ mul(slot='LR3') }}{% endfor %}
 SET LR10 LR11 ;;
 {% for i in range(3) %}
 LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ vec() }}
 ADD LR10 LR10 {{ cr.K }} ;;
 {% endfor %}
 INC LR11 1 ;;
 BLT.S LR11 {{ cr.K }} output_full ;;
 {{ store(tail) }}
 ADD LR4 LR4 LR12 ; DEC LR13 1 ;;
 BNE LR13 CR0 row_loop ;;
 HALT ;;
output_full:
 {{ store(full) }}
 BLT.S CR0 CR1 output_loop ;;
