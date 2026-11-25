{% set q = cr.qf_in0 ~ '.L' %}
{% set f = cr.full ~ '.L' %}
{% set d = cr.active ~ '.L' %}
{% set s = cr.single ~ '.L' %}
{% set r = cr.root_qf ~ '.L' %}
{% set t = cr.tmp %}
{# Softmax is nonnegative; relu gives the rounded identity store. #}
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
{# Generate two dyadic terms for log2(e)/2 in the input format. #}
    SET LR0 CR0 ; SET LR6 CR0 ; SET LR14 CR0 ;;
    INC LR6 5 ; INC LR14 6 ; SET LR7 CR1 ;;
    SET LR5 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{ f }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ f }} {{ q }} {{ t }} LR0 ;;
    LD.MULT R0 LR0 {{ t }} ;;
{{ power(1, 'LR7') }}
{{ power(4, 'LR6') }}
{{ power(4, 'LR5') }}
{{ power(4, 'LR14') }}
    SET LR15 CR0 ;;
    INC LR15 7 ;;
{{ power(11, 'LR15') }}
{{ coefficient('LR7','LR6',7) }}
{{ coefficient('LR5','LR14',5) }}
    SET LR13 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR4 CR0 ; SET LR1 CR1 ;;
    INC LR13 128 ; INC LR10 128 ; INC LR11 128 ;;
    INC LR10 128 ; INC LR11 128 ;;
    INC LR11 128 ;;
    LD.MULT.CYCLIC LR6 {{ t }} LR0 ;;
    LD.MULT.CYCLIC LR14 {{ t }} LR13 ;;
row:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR11 ;;
    MULT.RC.VE LR11 CR1 0 LR0 {{ d }} {{ q }} ; AGG.MAX.FIRST LR0 {{ d }} ; ACTIVATE.QUANTIZE identity {{ s }} {{ q }} {{ t }} LR1 ; LD.MULT R0 LR6 {{ t }} ;;
    LD.MULT R1 LR1 {{ t }} ;;
{% for coeff in ['LR0', 'LR13'] %}
    MULT.RC.VV LR11 R0 0 LR0 {{ d }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR13 0 LR0 {{ d }} {{ q }} ; ACC.SUB ; LD.MULT R0 {{ 'LR15' if loop.last else 'LR14' }} {{ t }} ;;
{% endfor %}
    {# A common negative bias keeps rounded zero inside the exp2 domain. #}
    MULT.VE LR0 CR1 0 LR0 {{ d }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ d }} {{ r }} {{ t }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ t }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ d }} {{ r }} ; AGG.SUM.FIRST LR0 {{ d }} ; ACTIVATE.QUANTIZE rsqrt {{ s }} {{ r }} {{ t }} LR1 ;;
    LD.MULT R1 LR1 {{ t }} ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ d }} {{ r }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ d }} {{ r }} {{ t }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ t }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ d }} {{ r }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ 'relu' if act == 'identity' else act }} {{ d }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
    BNE LR4 {{ cr.rows }} row ;;
    HALT ;;
