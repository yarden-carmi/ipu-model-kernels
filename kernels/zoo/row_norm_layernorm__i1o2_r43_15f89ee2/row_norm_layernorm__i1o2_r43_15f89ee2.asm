{% set q = cr.qf_gamma ~ '.L' %}
{% set iq = cr.qf_in0 ~ '.L' %}
{% set full = cr.tail ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set slots = ['LR0','LR3','LR4'] %}
{% set k = (channels + 127) // 128 %}
{% macro addr(reg,n) %}
 SET {{ reg }} CR0 ;;
 {% if n %}INC {{ reg }} {{ n }} ;;{% endif %}
{% endmacro %}
{% macro scalar(op='ADD',imm='CR1',fmt=q) %}
 MULT.VE LR0 {{ imm }} 0 LR0 {{ full }} {{ fmt }} ; ACC.{{ op }}
{% endmacro %}
{% macro mac(slot,op='ADD',src='R0') %}
 MULT.RC.VV {{ slot }} {{ src }} 0 LR0 {{ full }} {{ q }} ; ACC.{{ op }}
{% endmacro %}
{% macro encode(reg,pieces,ds=full) %}
 ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% for i in range(pieces-1) %}
 LD.MULT R0 {{ reg }} {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC {{ reg }} 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} {{ reg }} ;;
 {% endfor %}
{% endmacro %}
{% macro save(n,pieces=2) %}
 {{ addr('LR1',n) }}{{ encode('LR1',pieces) }}
{% endmacro %}
{% macro average() %}
 {{ encode('LR0',1) }}
 LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR1 CR0 ;;
 {{ scalar('SUB') }} ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR0 {{ cr.crow }} LR0 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ; SET LR10 CR0 ;;
 {{ scalar('SUB') }} ; INC LR1 1 ; INC LR10 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR10 {{ cr.crow }} LR3 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR10 CR0 ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 MULT.RC.VE {{ slot }} LR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if i == 0 and loop.first %}.FIRST{% endif %}
 {% if i == 0 and loop.index == 2 %} ; LD.MULT.CYCLIC LR1 {{ cr.crow }} LR4{% endif %}
 {% if loop.last and i < 2 %} ; INC LR10 1 ; LD.MULT R0 LR10 {{ cr.tmp }}{% endif %} ;;
 {% endfor %}
 {% endfor %}
{% endmacro %}
{% macro load(n,cy=false) %}
 {{ addr('LR1',n) }}
 {% if cy %}LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
 {% else %}LD.MULT R0 LR1 {{ cr.tmp }} ;;{% endif %}
{% endmacro %}
{% macro sum_chunk(ds,first=false,advance=false) %}
 LD.MULT R0 LR5 {{ cr.in0 }}{% if advance %} ; INC LR5 1{% endif %} ;;
 MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ iq }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }}
{% endmacro %}
{% macro center(ds,advance) %}
 LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR1 LR8 ;;
 {{ scalar('ADD.FIRST',fmt=iq) }} ; LD.MULT R0 LR1 {{ cr.tmp }}{% if advance %} ; INC LR5 1{% endif %} ;;
 {% for i in range(3) %}
 {{ scalar('SUB') }}{% if not loop.last %} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }}{% else %} ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9{% endif %} ;;
 {% endfor %}
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR9 1 ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR9 ;;
{% endmacro %}
{% macro variance(first=false) %}
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR0 ; SET LR10 LR9 ;;
 LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR3 ; INC LR9 1 ;;
 LD.MULT R0 LR10 {{ cr.tmp }} ;;
 {% for i in range(4) %}
 MULT.RC.VV {{ slots[i % 2] }} R0 0 LR0 {{ full }} {{ q }} ; AGG.SUM{% if first and i == 0 %}.FIRST{% endif %} LR0 {{ full }}
 {% if i == 1 %} ; LD.MULT R0 LR9 {{ cr.tmp }}{% elif i == 3 %} ; INC LR9 1{% endif %}
 {% if not loop.last %};;{% endif %}
 {% endfor %}
{% endmacro %}
{# Multiply two-piece factors using the fourth cyclic slot for the transient. #}
{% macro affine(ds,advance) %}
 SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.gamma }} ;;
 {% for i in range(3) %}
 {% for slot in slots %}
 {{ mac(slot,'ADD.FIRST' if i == 0 and loop.first else 'ADD') }}{% if loop.last and i < 2 %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.gamma }}{% elif i == 2 and loop.last %} ; SET LR1 LR12 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
 {% endfor %}
 {% endfor %}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR15 ;;
 LD.MULT R0 LR9 {{ cr.tmp }} ;;
 {{ mac('LR15','ADD.FIRST') }} ; INC LR9 1 ; LD.MULT R1 LR9 {{ cr.tmp }} ;;
 {{ mac('LR15',src='R1') }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ;;
 {{ mac('LR15') }} ; SET LR10 LR11 ; LD.MULT R0 LR10 {{ cr.beta }} ;;
 {{ mac('LR15',src='R1') }} ; INC LR9 1 ;;
 {% for i in range(3) %}
 {{ scalar() }}{% if not loop.last %} ; ADD LR10 LR10 {{ cr.K }} ; LD.MULT R0 LR10 {{ cr.beta }}{% else %} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14{% endif %} ;;
 {% endfor %}
 INC LR14 1{% if advance %} ; INC LR11 1{% endif %}
{% endmacro %}

 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 INC LR3 128 ; SET LR14 CR0 ; SET LR8 CR0 ;;
 SET LR4 LR3 ; INC LR8 27 ; SET LR7 CR0 ;;
 INC LR4 128 ; INC LR7 32 ; SET LR12 CR0 ;;
 ADD LR15 LR4 LR3 ; INC LR12 9 ;;
row_loop:
 SET LR5 LR2 ; SET LR9 LR7{% if k > 2 %} ; ADD LR6 LR2 {{ cr.K }}{% endif %} ;;
 {{ scalar('ADD.FIRST','CR0') }}{% if k > 2 %} ; DEC LR6 1{% endif %} ;;
 {% if k <= 2 %}
 {% for i in range(k) %}{{ sum_chunk(tail if loop.last else full,loop.first,not loop.first) }} ;;{% endfor %}
 {% else %}
 {{ sum_chunk(full,true) }} ;;
 INC LR5 1 ;;
sum_loop:
 BEQ LR5 LR6 sum_tail ;;
 {{ sum_chunk(full) }} ; INC LR5 1 ; B sum_loop ;;
sum_tail:
 {{ sum_chunk(tail) }} ;;
 {% endif %}
 {{ average() }}
 SET LR1 LR8 ; SET LR5 LR2 ;;
 {{ encode('LR1',3) }}
 {% if k <= 2 %}
 {% for i in range(k) %}{{ center(tail if loop.last else full,not loop.last) }}{% if not loop.last %}INC LR9 1 ;;{% endif %}{% endfor %}
 {% else %}
center_loop:
 BEQ LR5 LR6 center_tail ;;
 {{ center(full,true) }}
 INC LR9 1 ; B center_loop ;;
center_tail:
 {{ center(tail,false) }}
 {% endif %}
 SET LR9 LR7 ; SET LR5 LR2 ; {{ scalar('ADD.FIRST','CR0') }} ;;
 {% if k <= 2 %}
 {% for i in range(k) %}{{ variance(loop.first) }} ;;{% endfor %}
 {% else %}
 {{ variance(true) }} ; INC LR5 1 ;;
variance_loop:
 {{ variance() }} ; INC LR5 1 ; BLT.S LR5 LR6 variance_loop ;;
 {% endif %}
 {{ average() }}
 LD.MULT R0 LR0 {{ cr.epsilon }} ; SET LR1 CR0 ;;
 {{ scalar() }} ; INC LR1 8 ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
 {{ save(11) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ scalar('SUB') }} ;;{{ save(22,1) }}
 {{ load(8,true) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0','ADD.FIRST') }} ;;{{ save(13) }}
 {{ addr('LR10',11) }}
 LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR3 ; DEC LR1 1 ;;
 LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR3','ADD.FIRST') }} ; INC LR1 1 ; LD.MULT R1 LR1 {{ cr.tmp }} ;;
 {{ mac('LR3',src='R1') }} ; INC LR10 1 ; LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR3 ;;
 {{ mac('LR3') }} ;;
 {{ mac('LR3',src='R1') }} ; INC LR10 10 ; LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR3 ;;
 {{ mac('LR3') }} ;;{{ save(15) }}
 LD.MULT R0 LR1 {{ cr.tmp }} ; DEC LR1 1 ;;
 {{ mac('LR0','ADD.FIRST') }} ; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
 {{ mac('LR0') }} ;;{{ save(17) }}
 MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ; DEC LR1 1 ;;
 MULT.RC.VE LR0 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; LD.MULT R1 LR1 {{ cr.tmp }} ; INC LR1 1 ;;
 {{ scalar('SUB',cr.half) }} ;;
 MULT.VE LR3 {{ cr.half }} 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; INC LR1 1 ;;
 {{ encode('LR1',3) }}
 DEC LR1 2 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ; SET LR11 CR0 ; SET LR9 LR7 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR3 ; SET LR5 LR2 ;;
 INC LR1 1 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR4 ;;
 {% if k <= 2 %}
 {% for i in range(k) %}{{ affine(tail if loop.last else full,not loop.last) }} ;;{% endfor %}
 {% else %}
affine_loop:
 BEQ LR5 LR6 affine_tail ;;
 {{ affine(full,true) }} ; INC LR5 1 ; B affine_loop ;;
affine_tail:
 {{ affine(tail,false) }} ;;
 {% endif %}
 ADD LR2 LR2 LR13 ; BGE.S LR14 {{ cr.M }} finished ;;
 BLT.S LR2 {{ cr.M }} row_loop ;;
 SUB LR2 LR2 {{ cr.M }} ;;
 ADD LR2 LR2 {{ cr.K }} ; B row_loop ;;
finished:
 HALT ;;
