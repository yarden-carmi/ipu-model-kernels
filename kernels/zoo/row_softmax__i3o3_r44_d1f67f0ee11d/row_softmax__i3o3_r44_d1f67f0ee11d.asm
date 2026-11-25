{% set q = cr.qf_in0 ~ '.L' %}
{% set s = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% set scalar = cr.scalar ~ '.L' %}
{% set act = 'relu' if act_out0 | default('identity') == 'identity' else act_out0 %}

{# Build two representable dyadic terms for log2(e)/2. #}
{% macro power(delta,slot) %}
{% for i in range(delta) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} {{ slot }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro coefficient(base,unit,count) %}
    LD.MULT R0 {{ base }} {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 {{ unit }} {{ cr.tmp }} ;;
{% for i in range(count) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ unit }}{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR1 ; SET LR6 CR0 ;;
    SET LR14 CR0 ; SET LR5 CR0 ;;
    INC LR6 5 ; INC LR14 6 ; SET LR7 CR1 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{{ power(1,'LR7') }}
{{ power(4,'LR6') }}
{{ power(4,'LR5') }}
{{ power(4,'LR14') }}
{{ coefficient('LR7','LR6',7) }}
{{ coefficient('LR5','LR14',5) }}
    SET LR13 CR0 ; SET LR10 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ; SET LR8 CR0 ;;
    DEC LR4 1 ; SET LR9 {{ cr.rows }} ;;
    DEC LR9 1 ;;
    INC LR13 128 ; INC LR10 128 ;;
    INC LR10 128 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR13 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;

row:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR8 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for index in ['LR0','LR13'] %}
    MULT.RC.VV {{ index }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ index }} LR13 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ s }} {{ cr.tmp }} LR0{% endif %} ;;
{% endfor %}
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ ds }} {{ s }} ; AGG.SUM.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE reciprocal {{ scalar }} {{ s }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ ds }} {{ s }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ s }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ s }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR4 1 ;;
    BEQ LR4 LR9 done ;;
    BEQ LR8 CR0 second ;;
    SET LR8 CR0 ; INC LR2 1 ; B row ;;
second:
    SET LR8 {{ cr.n }} ; B row ;;
done:
    HALT ;;
