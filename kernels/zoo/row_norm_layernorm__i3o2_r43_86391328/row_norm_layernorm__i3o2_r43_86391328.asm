{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set K = cr.config ~ '.L' %}
{% macro at(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro mac(slot='LR0',first=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ at('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
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
{% set slots = ['LR0','LR6','LR10'] %}
{% macro load_parts(n,count=3) %}
 {{ at('LR1',n) }}
 {% for slot in slots[:count] %}
 LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ slot }}{% if not loop.first %} ; INC LR1 1{% endif %} ;;
 {% endfor %}
{% endmacro %}
{% macro average() %}
 // AGG.SUM leaves its running total in lane zero. Broadcast its residual parts.
 {{ save(0,3) }}
 {% for j in range(3) %}
 {{ load(j) }}
 MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
 {% endfor %}
 {{ save(3,3) }}
 {{ at('LR6',128) }}
 ADD LR10 LR6 LR6 ;;
 {{ load_parts(3) }}
 SET LR14 CR0 ; LD.MULT R0 LR0 {{ cr.crow }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; INC LR14 1 ; LD.MULT R0 LR14 {{ cr.crow }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro product(a,b,dest) %}
 {% for i in range(2) %}
 {{ load(a+i,true) }}{{ load(b) }}
 {{ mac(first=loop.first) }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac() }} ;;
 {% endfor %}
 {{ save(dest) }}
{% endmacro %}
{% macro sum_chunk(ds) %}
 {% for i in range(2) %}
 LD.MULT R0 LR5 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ ds }} ; INC LR5 1 ;;
 {% endfor %}
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR4 CR0 ;;
row_loop:
 // Linear spatial index = packed row LR3 plus lane LR4.
 // Walk channels at fixed spatial index and scatter into channel order.
 SET LR5 LR3 ; ADD LR11 LR3 LR7 ;;
 {{ at('LR9',32) }}
gather_chunk:
 ADD LR6 LR5 LR13 ; SET LR15 CR0 ;;
 SET LR14 CR0 ; SET LR1 CR0 ;;
 BLT.S LR6 LR11 gather_lane ;;
 SET LR6 LR11 ;;
gather_lane:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 MULT.EE LR4 CR1 0 LR0 {{ full }} {{ iq }} ; ACC.RESHAPE LRD0 LRD14 7 ; ADD LR5 LR5 LR8 ;;
 ADDBI LRD14 1 ; BLT.S LR5 LR6 gather_lane ;;
 BEQ LR5 LR11 gather_tail ;;
 {{ encode('LR9',2) }}
 INC LR9 1 ; B gather_chunk ;;
gather_tail:
 {{ encode('LR9',2,tail) }}
 INC LR9 1 ;;
 SET LR11 LR9 ;;
 DEC LR11 2 ;;
 {{ at('LR5',32) }}
 {{ scalar(first=true,imm='CR0') }} ;;
 BEQ LR5 LR11 sum_tail ;;
sum_loop:
 {{ sum_chunk(full) }}
 BLT.S LR5 LR11 sum_loop ;;
sum_tail:
 {{ sum_chunk(tail) }}
 {{ average() }}{{ save(27,3) }}

 {{ at('LR5',32) }}
center_loop:
 SET LR1 CR0 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ scalar(first=true) }} ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.tmp }} ;;
 {{ scalar() }} ; DEC LR5 1 ; INC LR1 27 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {{ scalar('SUB') }}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 BEQ LR5 LR11 center_tail ;;
 {{ encode('LR9',2) }}
 INC LR9 1 ; INC LR5 2 ; B center_loop ;;
center_tail:
 {{ encode('LR9',2,tail) }}

 {{ at('LR9',32) }}
 ADD LR9 LR9 {{ K }} ; SET LR5 CR0 ;;
 ADD LR9 LR9 {{ K }} ;;
 {{ scalar(first=true,imm='CR0') }} ;;
variance_loop:
 SET LR1 LR9 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR6 ;;
 {% for i in range(2) %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {% for slot in slots[:2] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ;;
 {% endfor %}
 INC LR9 1 ;;
 {% endfor %}
 INC LR5 1 ;;
 BLT.S LR5 {{ K }} variance_loop ;;
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }} ;;
 {{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}

 // Newton correction, using the full variance rather than its rounded value.
 {{ load(8,true) }}{{ load(8) }}{{ mac(first=true) }} ;;
 {{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mac(first=true) }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac() }} ;;
 {{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}
 {{ load(n) }}{{ scalar('SUB',imm=cr.half) }} ;;
 {% endfor %}
 {{ save(19,3) }}

 {{ at('LR9',32) }}
 ADD LR9 LR9 {{ K }} ; SET LR5 LR2 ; SET LR11 CR0 ;;
 ADD LR9 LR9 {{ K }} ; ADD LR14 LR2 {{ K }} ;;
 DEC LR14 1 ;;
 {{ load_parts(19) }}
output_loop:
 SET LR15 LR11 ; LD.MULT R0 LR11 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; ADD LR15 LR15 {{ K }} ; LD.MULT R0 LR15 {{ cr.gamma }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ save(23) }}
 ADD LR15 LR6 LR10 ;;
 {% for i in range(2) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR15 ;;
 {{ load(23) }}
 {{ mac('LR15',loop.first) }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR15') }} ; INC LR9 1 ;;
 {% endfor %}
 SET LR15 LR11 ; LD.MULT R0 LR11 {{ cr.beta }} ;;
 {% for i in range(3) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR15 LR15 {{ K }} ; LD.MULT R0 LR15 {{ cr.beta }}{% endif %} ;;
 {% endfor %}
 BNE LR5 LR14 output_full ;;
 {{ store(tail) }}
 INC LR14 1 ;;
 BEQ LR14 {{ cr.M }} finish ;;
 INC LR4 1 ; ADD LR2 LR2 LR12 ;;
 BLT.S LR4 {{ cr.config }}.H next_position ;;
 SET LR4 CR0 ; INC LR3 1 ;;
next_position:
 BLT.S LR2 {{ cr.M }} row_loop ;;
 SUB LR2 LR2 {{ cr.M }} ;;
 ADD LR2 LR2 {{ K }} ; B row_loop ;;
output_full:
 {{ store(full) }}
 INC LR5 1 ; INC LR11 1 ; B output_loop ;;
finish:
 HALT ;;
