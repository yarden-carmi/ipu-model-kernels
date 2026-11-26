{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set work = cr.work ~ '.L' %}
{% set ds = cr.lanes ~ '.L' %}
{% set scalar = cr.lanes ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set act = act_out0 | default('identity') %}
{% macro coefficient(power, count, row) %}
    LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR1 {{ power }} ; INC LR2 {{ row }} ; MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
power_{{ row }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR1 1 ;;
    BNE LR1 CR0 power_{{ row }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR2 ;;
    LD.MULT R0 LR2 {{ cr.tmp }} ; INC LR1 {{ count }} ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
scale_{{ row }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR1 1 ;;
    BNE LR1 CR0 scale_{{ row }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR2 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
{{ coefficient(5,23,1) }}
{{ coefficient(13,21,2) }}
    INC LR3 128 ;;
    ADD LR4 LR3 LR3 ;;
    LD.MULT.CYCLIC LR2 {{ cr.tmp }} LR4 ; ADD LR5 LR4 LR3 ;;
    DEC LR2 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.tmp }} LR3 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ;;
{% macro softmax(window) %}
    MULT.RC.VE {{ window }} CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR0 ;;
    MULT.RC.VE {{ window }} CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR2 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
    LD.MULT R1 LR2 {{ cr.tmp }} ;;
{% for coeff in ['LR4','LR3'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR3 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
{% endfor %}
    MULT.RC.VE LR4 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR5 ;;
    MULT.RC.VS LR5 0 LR0 {{ ds }} {{ work }} ; AGG.SUM.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE rsqrt {{ scalar }} {{ work }} {{ cr.tmp }} LR2 ;;
    LD.MULT R1 LR2 {{ cr.tmp }} ;;
    MULT.RC.VE LR5 LR3 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR5 ;;
    MULT.RC.VS LR5 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
row:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{{ softmax('LR8') }}
    INC LR9 1 ;;
    BEQ LR9 {{ cr.in0_d2 }} next_group ;;
    BNE LR8 CR0 second ;;
    SET LR8 {{ cr.n }} ;;
    BEQ CR0 CR0 check ;;
second:
    SET LR8 CR0 ; INC LR6 1 ;;
    BEQ CR0 CR0 check ;;
next_group:
    SET LR9 CR0 ; SET LR8 CR0 ; INC LR6 1 ;;
check:
    BLT.S LR7 {{ cr.rows }} row ;;
    HALT ;;
