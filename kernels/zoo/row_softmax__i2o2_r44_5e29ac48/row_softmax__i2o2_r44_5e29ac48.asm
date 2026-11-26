{% set q = cr.qf_in0 ~ '.L' %}
{% set w = cr.scratch_qf ~ '.L' %}
{% set z = cr.scratch_qf ~ '.H' %}
{% set p = cr.nm ~ '.H' %}
{% set nm = cr.nm ~ '.L' %}
{% set f = cr.full ~ '.L' %}
{% set act = act_out0 | default('identity') %}
    SET LR0 CR0 ; SET LR1 CR1 ; SET LR2 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{% for i in range(4) %}
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for i in range(7) %}
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ f }} {{ q }} {{ cr.tmp }} LR1{% endif %} ;;
{% endfor %}
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    SET LR10 CR0 ;;
    INC LR10 2 ;;
    SET LR15 CR0 ;;
    INC LR15 7 ;;
    MULT.VE LR0 CR0 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ cr.tmp }} LR15 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
    INC LR11 3 ; INC LR12 4 ; INC LR13 5 ;;
    SET LR14 CR0 ;;
    INC LR14 6 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ;;
{% for i in range(14) %}
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.SUB{% if i == 7 %} ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ cr.tmp }} LR11{% elif i == 9 %} ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ cr.tmp }} LR12{% elif i == 11 %} ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ cr.tmp }} LR13{% elif i == 13 %} ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ cr.tmp }} LR14{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR11 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR12 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD ; LD.MULT R0 LR13 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD ; LD.MULT R0 LR14 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ f }} {{ q }} {{ cr.tmp }} LR11 ;;
{% macro group(ds) %}
    SUB LR6 LR3 {{ cr.C }} ; SET LR7 CR0 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; ADD LR6 LR6 {{ cr.C }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.MAX.FIRST ; INC LR7 1 ; BEQ CR1 {{ cr.n }} max_done_{{ ds }} ;;
max_loop_{{ ds }}:
    LD.MULT R0 LR6 {{ cr.in0 }} ; ADD LR6 LR6 {{ cr.C }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.MAX ; INC LR7 1 ; BLT.S LR7 {{ nm }} max_loop_{{ ds }} ;;
max_done_{{ ds }}:
    ACTIVATE.QUANTIZE identity {{ f }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ f }} {{ q }} {{ cr.tmp }} LR14 ;;
    SET LR8 CR0 ;;
    INC LR8 128 ;;
    INC LR8 128 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR8 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR11 {{ cr.tmp }} LR9 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ; SUB LR6 LR3 {{ cr.C }} ; SET LR7 CR0 ;;
exp_loop_{{ ds }}:
    LD.MULT R0 LR6 {{ cr.in0 }} ; ADD LR6 LR6 {{ cr.C }} ;;
    MULT.VE LR9 {{ cr.quarter }} 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{ cr.quarter }} 0 LR0 {{ f }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VE LR8 {{ cr.quarter }} 0 LR2 {{ f }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE relu6 {{ f }} {{ q }} {{ cr.tmp }} LR10 ;;
    LD.MULT R0 LR15 {{ cr.tmp }} ;;
{% for i in range(6) %}
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE relu {{ f }} {{ z }} {{ cr.tmp }} LR12{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR12 {{ cr.tmp }} ;;
{% for i in range(3) %}
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ z }} ; ACC.SUB{% if loop.first %}.FIRST{% endif %}{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ w }} {{ cr.tmp }} LR12{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR10 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR2 {{ f }} {{ q }} ; ACC.SUB.FIRST ;;
    MULT.RC.VV LR9 R0 0 LR2 {{ f }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ p }} {{ cr.tmp }} LR13 ;;
    LD.MULT.CYCLIC LR13 {{ cr.tmp }} LR8 ;;
    MULT.RC.VS LR8 0 LR2 {{ f }} {{ p }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ f }} {{ w }} {{ cr.tmp }} LR13 ;;
    LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR8 ;;
    LD.MULT R0 LR13 {{ cr.tmp }} ;;
    MULT.RC.VV LR8 R0 0 LR2 {{ f }} {{ w }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ f }} {{ w }} {{ cr.exps }} LR7 ; LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR8 ;;
    INC LR7 1 ; BLT.S LR7 {{ nm }} exp_loop_{{ ds }} ;;
    SET LR7 CR0 ;;
    DEC LR7 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.exps }} LR0 ; INC LR7 1 ;;
    MULT.RC.VS LR0 0 LR2 {{ f }} {{ w }} ; ACC.ADD.FIRST ; BEQ CR1 {{ cr.n }} sum_done_{{ ds }} ;;
sum_loop_{{ ds }}:
    LD.MULT.CYCLIC LR7 {{ cr.exps }} LR0 ; INC LR7 1 ;;
    MULT.RC.VS LR0 0 LR2 {{ f }} {{ w }} ; ACC.ADD ; BLT.S LR7 {{ nm }} sum_loop_{{ ds }} ;;
sum_done_{{ ds }}:
    LD.MULT R0 LR15 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.MAX ; ACTIVATE.QUANTIZE rsqrt {{ f }} {{ w }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ; SET LR7 CR0 ; SUB LR6 LR3 {{ cr.C }} ;;
    DEC LR7 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.exps }} LR0 ; INC LR7 1 ;;
store_loop_{{ ds }}:
    MULT.RC.VV LR0 R1 0 LR2 {{ f }} {{ w }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ f }} {{ w }} {{ cr.tmp }} LR12 ;;
    LD.MULT.CYCLIC LR12 {{ cr.tmp }} LR0 ;;
    MULT.RC.VS LR0 0 LR2 {{ f }} {{ w }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ; LD.MULT.CYCLIC LR7 {{ cr.exps }} LR0 ; INC LR7 1 ; ADD LR6 LR6 {{ cr.C }} ; BLT.S LR7 {{ nm }} store_loop_{{ ds }} ;;
{% endmacro %}
group_loop:
    ADD LR8 LR4 CR1 ;;
    BEQ LR8 {{ cr.C }} last_chunk ;;
{{ group(cr.full ~ '.L') }}
    BEQ CR0 CR0 next_group ;;
last_chunk:
{{ group(cr.tail ~ '.L') }}
next_group:
    INC LR3 1 ; INC LR4 1 ; INC LR5 1 ;;
    BEQ LR4 {{ cr.C }} next_batch ;;
    BLT.S LR5 {{ cr.groups }} group_loop ;;
    HALT ;;
next_batch:
    SET LR4 CR0 ; SET LR3 LR6 ;;
    INC LR3 1 ; BLT.S LR5 {{ cr.groups }} group_loop ;;
    HALT ;;
