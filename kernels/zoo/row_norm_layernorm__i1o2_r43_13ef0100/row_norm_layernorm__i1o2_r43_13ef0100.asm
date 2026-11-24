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
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro mac(slot,first=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro load_parts(n,count=3) %}
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
{% macro average() %}
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ load_parts(3) }}
 SET LR10 CR0 ;;
 LD.MULT R0 LR10 {{ cr.crow }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; LD.MULT R0 LR10 {{ cr.crow }} ; INC LR10 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 SET LR7 CR0 ; SET LR10 CR0 ;;
 INC LR7 {{ a }} ; INC LR10 {{ b }} ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac('LR0',true) }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ; INC LR7 1 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; DEC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% if a == 11 %}
 {{ mac('LR0') }} ; INC LR7 10 ; LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ; DEC LR10 1 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% endif %}
 {{ mac('LR0') }} ;;
 {{ save(dest) }}
{% endmacro %}
{% macro reset_chunks() %}
 SET LR5 LR2 ; SET LR9 CR0 ;;
 INC LR9 32 ;;
{% endmacro %}
{% macro sum_chunk(ds) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM LR0 {{ ds }} ;;
{% endmacro %}
{% macro advance(label) %}
 INC LR5 1 ;;
 BLT.S LR5 LR6 {{ label }} ;;
{% endmacro %}
{% set k = (channels + 127) // 128 %}
{% set packed_base = 33 + 2 * k %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ; SET LR14 CR0 ;;
 SET LR4 LR3 ; SET LR8 CR0 ;;
 INC LR4 128 ; INC LR8 {{ packed_base }} ;;
row_loop:
 ADD LR6 LR2 {{ cr.K }} ;;
 DEC LR6 1 ;;
 {{ reset_chunks() }}{{ scalar(first=true,imm='CR0') }} ;;
 BEQ LR5 LR6 sum_tail ;;
sum_loop:
 {{ sum_chunk(full) }}
 {{ advance('sum_loop') }}
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

 {# Refine the table estimate with two Newton corrections. #}
 {{ load(8,true) }}{{ load(8) }}{{ mac('LR0',true) }} ;;{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mac('LR0',true) }} ;;
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ;;{{ save(17) }}
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
 SET LR11 CR0 ; DEC LR6 1 ;;
affine_loop:
 {{ load_parts(19) }}
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; LD.MULT R0 LR10 {{ cr.gamma }} ; ADD LR10 LR10 {{ cr.K }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(9,2) }}
 {{ load_parts(9,2) }}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for i in range(2) %}
 {% for slot in slots[:2] %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 1 %} ; LD.MULT R0 LR9 {{ cr.tmp }} ; INC LR9 1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ; SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 BEQ LR5 LR6 affine_tail ;;
 {{ encode('LR8',2) }}
 INC LR8 1 ; INC LR5 1 ; INC LR11 1 ; BEQ LR0 CR0 affine_loop ;;
affine_tail:
 {{ encode('LR8',2,tail) }}
 INC LR8 1 ; ADD LR14 LR14 {{ cr.K }} ; ADD LR2 LR2 LR13 ;;
 BGE.S LR14 {{ cr.M }} pack_start ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 SUB LR2 LR2 {{ cr.M }} ;;
 ADD LR2 LR2 {{ cr.K }} ; BEQ LR0 CR0 row_loop ;;

{# Stream scratch chunks into output rows. The loaded chunk occupies the
   middle cyclic slot with zeros on either side, so a shifted window can
   contribute a prefix or suffix without touching other output lanes. #}
{% macro clear() %}
 MULT.RC.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro contribute() %}
 {% for i in range(2) %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 MULT.RC.VE LR10 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% endfor %}
 DEC LR1 1 ;;
{% endmacro %}
{% macro store() %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
{% endmacro %}
pack_start:
 {{ clear() }}
 {{ at('LR1',32 + 2*k) }}
 {{ encode('LR1',1) }}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 INC LR1 1 ; SET LR2 CR0 ;;
pack_group:
 SET LR14 LR12 ; SET LR5 CR0 ;;
pack_row:
 SET LR11 {{ cr.K }} ;;
pack_chunk:
 SET LR6 LR3 ; DEC LR11 1 ;;
 BNE LR11 CR0 pack_length_ready ;;
 {% if channels % 128 %}
 {{ at('LR6',channels % 128) }}
 {% endif %}
pack_length_ready:
 SUB LR10 LR3 LR5 ;;
 {{ contribute() }}
 ADD LR5 LR5 LR6 ;;
 BLT.S LR5 LR3 pack_next ;;
 {{ store() }}
 {{ clear() }}
 SUB LR5 LR5 LR3 ;;
 BEQ LR5 CR0 pack_next ;;
 SUB LR10 LR6 LR5 ;;
 ADD LR10 LR10 LR3 ;;
 {{ contribute() }}
pack_next:
 INC LR1 2 ; BNE LR11 CR0 pack_chunk ;;
 DEC LR14 1 ;;
 BNE LR14 CR0 pack_row ;;
 BEQ LR5 CR0 pack_group_done ;;
 {{ store() }}
 {{ clear() }}
pack_group_done:
 DEC LR15 1 ;;
 BNE LR15 CR0 pack_group ;;
 HALT ;;
