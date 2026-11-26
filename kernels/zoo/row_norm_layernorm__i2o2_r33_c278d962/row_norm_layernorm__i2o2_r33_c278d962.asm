{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
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
{% macro scalar(op='ADD',first=false,imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}{% if first %}.FIRST{% endif %}
{% endmacro %}
{% macro mul(first=false) %}
 {{ mac('LR0',first) }} ;;
{% endmacro %}
{% macro mac(slot,first=false) %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{% endmacro %}
{% set slots = ['LR0','LR3','LR4'] %}
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
 SET LR10 CR0 ;;
 {% for slot in slots %}
 LD.MULT.CYCLIC LR10 {{ cr.crow }} {{ slot }}{% if not loop.first %} ; INC LR10 1{% endif %} ;;
 {% endfor %}
 SET LR1 CR0 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 MULT.RC.VE {{ slot }} LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}{% if loop.last and i < 2 %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% endif %} ;;
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
 {{ mul() }}
 {{ save(dest) }}
{% endmacro %}
{% macro reset_chunks() %}
 SET LR5 LR2 ; SET LR9 LR15 ;;
{% endmacro %}
{% macro store(ds) %}
 ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ;;
 SET LR4 LR3 ;;
 INC LR4 128 ;;
 SET LR8 LR4 ;;
 INC LR8 128 ;;
 SET LR13 {{ cr.K }} ;;
 DEC LR13 1 ; SET LR15 CR0 ; SET LR14 CR0 ;;
 INC LR15 32 ; INC LR14 9 ;;
row_loop:
 ADD LR6 LR2 LR13 ; SET LR5 LR2 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {% if channels % 128 %}
 BEQ LR5 LR6 sum_first_tail ;;
 {% endif %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM.FIRST LR0 {{ full }}{% if channels > 128 %} ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }}{% endif %} ;;
 {% if channels % 128 and channels > 128 %}BEQ LR5 LR6 sum_tail ;;{% endif %}
 {% if channels > 128 + (channels % 128) %}
sum_loop:
 {% if channels % 128 %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ;;
 BLT.S LR5 LR6 sum_loop ;;
 {% else %}
 MULT.VE LR0 CR1 0 LR0 {{ full }} {{ iq }} ; AGG.SUM LR0 {{ full }} ; BEQ LR5 LR6 sum_done ;;
 INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in0 }} ; B sum_loop ;;
 {% endif %}
 {% endif %}
 {% if channels % 128 %}
 {% if channels > 128 %}
 sum_tail:
 MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ iq }} ; AGG.SUM LR0 {{ tail }} ; B sum_done ;;
 {% endif %}
 sum_first_tail:
 MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ iq }} ; AGG.SUM.FIRST LR0 {{ tail }} ;;
 {% endif %}
sum_done:
 {{ average() }}{{ save(27,3) }}
 {{ reset_chunks() }}
 {{ load_parts(27) }}
center_loop:
 LD.MULT R0 LR5 {{ cr.in0 }} ;;
 {{ scalar(first=true,fmt=iq) }} ;;
 {% for slot in slots %}
 MULT.RC.VE {{ slot }} CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
 {% endfor %}
 {% if channels % 128 %}
 BNE LR5 LR6 center_full ;;
 {{ encode('LR9',2,tail) }}
 B variance_start ;;
 center_full:
 {% endif %}
 {{ encode('LR9',2) }}
 INC LR9 1 ; INC LR5 1 ; BLT.S LR5 LR6 center_loop ;;
variance_start:
 SET LR5 LR2 ; SET LR9 LR15 ; {{ scalar(first=true,imm='CR0') }} ;;
 variance_loop:
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ;;
 {% for slot in ['LR3','LR0','LR3'] %}
 MULT.RC.VV {{ slot }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM LR0 {{ full }}{% if loop.first %} ; LD.MULT R0 LR9 {{ cr.tmp }}{% elif loop.last %} ; INC LR9 1 ; INC LR5 1 ; BLT.S LR5 LR6 variance_loop{% endif %} ;;
 {% endfor %}
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ;;
 {{ scalar() }} ;;{{ at('LR1',8) }}
 ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(22,1) }}
 {{ load(8,true) }}{{ load(8) }}{{ mul(first=true) }}{{ save(13) }}
 {{ product(11,13,15) }}
 {{ load(8,true) }}{{ load(15) }}{{ mul(first=true) }}
 INC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mul() }}{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
 {% for n in [17,18] %}{{ load(n) }}{{ scalar('SUB',imm=cr.half) }} ;;{% endfor %}
 {{ save(19) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(21,1) }}
 {{ reset_chunks() }}
 SET LR11 CR0 ;;
 {{ load_parts(19) }}
output_loop:
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,i == 0 and loop.first) }}{% if loop.last and i < 2 %} ; LD.MULT R0 LR10 {{ cr.gamma }} ; ADD LR10 LR10 {{ cr.K }}{% elif loop.last %} ; SET LR1 LR14{% endif %} ;;
 {% endfor %}
 {% endfor %}
 {{ encode('LR1',2) }}
 LD.MULT R1 LR14 {{ cr.tmp }} ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR8 ;;
 {% for i in range(2) %}
 {% for reg in ['R1','R0'] %}
 MULT.RC.VV LR8 {{ reg }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}
 {% if loop.last and i == 0 %} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR8{% endif %} ;;
 {% endfor %}
 {% endfor %}
 INC LR9 1 ; SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {% for i in range(3) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% elif channels % 128 == 0 %} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5{% endif %} ;;
 {% endfor %}
 {% if channels % 128 %}
 BNE LR5 LR6 output_full ;;
 {{ store(tail) }}
 B row_next ;;
 output_full:
 {{ store(full) }}
 INC LR5 1 ; INC LR11 1 ; B output_loop ;;
 {% else %}
 INC LR5 1 ; INC LR11 1 ; BLT.S LR5 LR6 output_loop ;;
 {% endif %}
row_next:
 ADD LR2 LR6 CR1 ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 HALT ;;
