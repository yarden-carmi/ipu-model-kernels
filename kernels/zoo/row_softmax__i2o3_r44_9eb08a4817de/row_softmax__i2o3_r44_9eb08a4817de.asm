{% set q = cr.qf_in0 ~ '.L' %}
{% set f = cr.full ~ '.L' %}
{% set d = cr.active ~ '.L' %}
{% set s = cr.single ~ '.L' %}
{% set w = cr.work_qf ~ '.L' %}
{% set t = cr.tmp %}
{% set act = act_out0 | default('identity') %}
{% macro power(delta, slot) %}
{% for i in range(delta) %}
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ t }} {{ slot }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro coefficient(base, unit, count) %}
    LD.MULT R0 {{ base }} {{ t }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 {{ unit }} {{ t }} ;;
{% for i in range(count) %}
    MULT.VE LR0 CR1 0 LR0 {{ f }} {{ q }} ; ACC.ADD{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ f }} {{ q }} {{ t }} {{ unit }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{# Generate log2(e)/2 as two dyadic coefficients. #}
    SET LR0 CR0 ; SET LR6 CR0 ; SET LR14 CR0 ;;
    INC LR6 5 ; INC LR14 6 ; SET LR7 CR1 ;;
    SET LR5 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ t }} LR0 ;;
    LD.MULT R0 LR0 {{ t }} ;;
{{ power(1, 'LR7') }}
{{ power(4, 'LR6') }}
{{ power(4, 'LR5') }}
{{ power(4, 'LR14') }}
{{ coefficient('LR7', 'LR6', 7) }}
{{ coefficient('LR5', 'LR14', 5) }}
    SET LR13 CR0 ; SET LR10 CR0 ; SET LR4 CR0 ;;
    SET LR1 CR1 ; SET LR2 CR0 ; SET LR8 CR0 ;;
    INC LR13 128 ; INC LR10 128 ; SET LR12 CR0 ;;
    INC LR10 128 ;;
    LD.MULT.CYCLIC LR6 {{ t }} LR0 ;;
    LD.MULT.CYCLIC LR14 {{ t }} LR13 ;;
    SET LR6 CR0 ;;
    INC LR6 128 ;;
    INC LR6 128 ;;
    INC LR6 128 ;;
    LD.MULT.CYCLIC LR7 {{ t }} LR6 ;;
row:
    ADD LR9 LR12 LR0 ; SET LR11 CR0 ;;
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR8 CR1 0 LR0 {{ f }} {{ q }} ; AGG.MAX.FIRST LR0 {{ s }} ;;
max_loop:
    INC LR9 1 ; INC LR11 1 ;;
    BEQ LR11 {{ cr.n }} max_done ;;
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR8 CR1 0 LR0 {{ f }} {{ q }} ; AGG.MAX LR0 {{ s }} ;;
    BNE LR0 CR1 max_loop ;;
max_done:
    ACTIVATE.QUANTIZE identity {{ s }} {{ q }} {{ t }} LR1 ;;
    LD.MULT R1 LR1 {{ t }} ;;
    ADD LR9 LR12 LR0 ; SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR15 8 ;;
exponent:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
{% for coeff in ['LR0', 'LR13', 'LR0', 'LR13'] %}
    MULT.RC.VE {{ coeff }} LR13 0 LR0 {{ f }} {{ q }} ; ACC.SUB{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR8 0 LR0 {{ f }} {{ q }} ; ACC.ADD ;;
{% endfor %}
    MULT.RC.VE LR6 CR1 0 LR0 {{ f }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ s }} {{ w }} {{ t }} LR15 ;;
    INC LR9 1 ; INC LR11 1 ; INC LR15 1 ;;
    BNE LR11 {{ cr.n }} exponent ;;
    SET LR3 CR0 ; SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR15 8 ;;
    MULT.VE LR0 CR0 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ;;
sum:
    LD.MULT R0 LR15 {{ t }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ f }} {{ w }} ; AGG.SUM LR0 {{ s }} ;;
    INC LR15 1 ; INC LR11 1 ;;
    BNE LR11 {{ cr.n }} sum ;;
    ACTIVATE.QUANTIZE reciprocal {{ s }} {{ w }} {{ t }} LR1 ;;
    LD.MULT R1 LR1 {{ t }} ; SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR15 8 ;;
renormalize:
    LD.MULT.CYCLIC LR15 {{ t }} LR10 ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ f }} {{ w }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ s }} {{ w }} {{ t }} LR15 ;;
    INC LR15 1 ; INC LR11 1 ;;
    BNE LR11 {{ cr.n }} renormalize ;;
    SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR15 8 ;;
    MULT.VE LR0 CR0 0 LR0 {{ f }} {{ w }} ; ACC.ADD.FIRST ;;
resum:
    LD.MULT R0 LR15 {{ t }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ f }} {{ w }} ; AGG.SUM LR0 {{ s }} ;;
    INC LR15 1 ; INC LR11 1 ;;
    BNE LR11 {{ cr.n }} resum ;;
    ACTIVATE.QUANTIZE reciprocal {{ s }} {{ w }} {{ t }} LR1 ;;
    LD.MULT R1 LR1 {{ t }} ; SET LR11 CR0 ; SET LR15 CR0 ;;
    INC LR15 8 ;;
gather:
    LD.MULT.CYCLIC LR15 {{ t }} LR10 ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ f }} {{ w }} ; ACC.RESHAPE LRD0 LRD2 7 ;;
    INC LR15 1 ; INC LR11 1 ; ADDBI LRD2 1 ;;
    BNE LR11 {{ cr.n }} gather ;;
    ACTIVATE.QUANTIZE {{ 'relu' if act == 'identity' else act }} {{ d }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR8 1 ;;
    BNE LR8 {{ cr.in0_d2 }} next ;;
    SET LR8 CR0 ; ADD LR12 LR9 LR0 ;;
next:
    BNE LR4 {{ cr.rows }} row ;;
    HALT ;;
