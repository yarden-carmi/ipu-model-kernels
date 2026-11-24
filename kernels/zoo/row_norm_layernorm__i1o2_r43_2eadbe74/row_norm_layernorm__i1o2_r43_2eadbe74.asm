{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set slots = ['LR0','LR3','LR4'] %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q,ds=full) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ ds }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro mac(slot='LR0',first=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro parts(n,count=3) %}
 {{ at('LR1',n) }}
 {% for slot in slots[:count] %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }}{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(pieces-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ at('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro affine_product(table,stride) %}
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; LD.MULT R0 LR10 {{ table }} ; ADD LR10 LR10 {{ stride }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro average() %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ parts(3) }}
 SET LR10 CR0 ;;
 LD.MULT R0 LR10 {{ cr.crow }} ;;
 {{ affine_product(cr.crow,'CR1') }}
{% endmacro %}
{% macro product(a,b,dest) %}
 SET LR7 CR0 ; SET LR10 CR0 ;;
 INC LR7 {{ a }} ; INC LR10 {{ b }} ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac(first=true) }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac() }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; DEC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac() }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% if a == 11 %}
 {{ mac() }} ; INC LR7 10 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; DEC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% endif %}
 {{ mac() }} ;;{{ save(dest) }}
{% endmacro %}
{% macro reset_chunks() %}
 SET LR5 LR2 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
{% endmacro %}
{% macro sum_chunk(ds) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM LR0 {{ ds }} ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ;;
 {{ at('LR3',128) }}
 ADD LR4 LR3 LR3 ;;
 {{ at('LR8',96) }}
row_loop:
 ADD LR6 LR2 {{ cr.K }} ;;
 DEC LR6 1 ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }} ;;
 BEQ LR5 LR6 sum_tail ;;
sum_loop:
 {{ sum_chunk(full) }}
 INC LR5 1 ;;
 BLT.S LR5 LR6 sum_loop ;;
sum_tail:
 {{ sum_chunk(tail) }}
 {{ average() }}{{ save(27,3) }}

 {{ reset_chunks() }}
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 CR0 ;;
 {{ scalar(first=true,fmt=iq) }} ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for n in range(3) %}
 {{ scalar('SUB') }}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 BNE LR5 LR6 center_full ;;
 {{ encode('LR9',2,tail) }}
 BEQ LR0 CR0 variance_start ;;
center_full:
 {{ encode('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ; BEQ LR0 CR0 center_loop ;;

variance_start:
 INC LR6 1 ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }} ;;
variance_loop:
 SET LR1 LR9 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% for i in range(2) %}
 SET LR10 LR9 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for j in range(2) %}
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}
 {% if not loop.last %} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }}
 {% elif i < 1 %} ; INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0
 {% else %} ; INC LR9 2 ; INC LR5 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 BLT.S LR5 LR6 variance_loop ;;
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }} ;;{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(22,1) }}

 {# Refine the reciprocal square root using the retained variance. #}
 {{ load(8,true) }}{{ load(8) }}{{ mac(first=true) }} ;;{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mac(first=true) }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac() }} ;;{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }} ;;{% endfor %}
 {{ save(19) }}
 {{ product(19,19,13) }}{{ product(11,13,15) }}{{ product(19,15,17) }}
 {% for n in [19,20] %}
 {{ load(n,true) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }} ;;{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(21,1) }}

 {{ reset_chunks() }}
 SET LR7 CR0 ;;
affine_loop:
 {{ parts(19) }}
 SET LR10 LR7 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {{ affine_product(cr.gamma,cr.K) }}
 {{ save(9,2) }}
 {{ parts(9,2) }}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 {% for slot in slots[:2] %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 1 %} ; LD.MULT R0 LR9 {{ cr.tmp }} ; INC LR9 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ; SET LR10 LR7 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 {{ encode('LR8',2) }}
 INC LR8 1 ; INC LR7 1 ; INC LR5 1 ;;
 BLT.S LR5 LR6 affine_loop ;;
 {# The patches view visits spatial positions 0,4,8,... then 1,5,9,... #}
 ADD LR2 LR2 LR12 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 SUB LR2 LR2 {{ cr.M }} ;;
 ADD LR2 LR2 {{ cr.K }} ;;
 BLT.S LR2 LR12 row_loop ;;

 {# Replay each packed row's gather: residual first, leading plane second.
    Each reshape copies eight consecutive lanes, ignoring input padding. #}
{% macro gather(label,low) %}
 SET LR2 LR14 ; SET LR3 LR15 ;;
{{ label }}:
 {% if low %}ADD LR0 LR4 CR1 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
 {% else %}LD.MULT R0 LR4 {{ cr.tmp }} ;;{% endif %}
 SET LR0 LR14 ; SET LR1 LR15 ;;
 ADDB LRD0 LR5 ;;
 MULT.VE LR12 CR1 0 LR12 {{ full }} {{ q }} ; ACC.RESHAPE LRD0 LRD2 0 ;;
 ADDBI LRD2 8 ; INC LR5 8 ;;
 DEC LR6 8 ;;
 SET LR0 CR0 ; BEQ LR6 CR0 {{ label }}_next_item ;;
 INC LR0 128 ;;
 BLT.S LR5 LR0 {{ label }}_step ;;
 BEQ CR0 CR0 {{ label }}_next_chunk ;;
{{ label }}_next_item:
 SET LR6 LR11 ;;
{{ label }}_next_chunk:
 SET LR5 CR0 ; INC LR4 2 ;;
{{ label }}_step:
 BGE.S LR3 CR0 {{ label }} ;;
{% endmacro %}
 {{ at('LR4',96) }}
 SET LR5 CR0 ; SET LR6 LR11 ; SET LR7 CR0 ;;
 SET LR12 CR0 ;;
packed_loop:
 SET LR9 LR4 ; SET LR10 LR5 ; SET LR8 LR6 ;;
 {{ gather('gather_low',true) }}
 ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR12 ; SET LR4 LR9 ; SET LR5 LR10 ; SET LR6 LR8 ;;
 {{ gather('gather_hi',false) }}
 LD.MULT R0 LR12 {{ cr.tmp }} ; SET LR0 CR0 ;;
 {{ scalar() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
 INC LR7 1 ;;
 BLT.S LR7 LR13 packed_loop ;;
 HALT ;;
