{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro tiles(label) %}
    SET LR3 CR0 ;;
    BEQ LR3 LR8 {{ label }}_tail ;;
{{ label }}_loop:
{{ caller(full) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 {{ label }}_loop ;;
{{ label }}_tail:
{{ caller(tail) }}
{% endmacro %}

{# Generate dyadic coefficients without folded constants. #}
{% macro coefficient(power,count,slot) %}
{{ imm('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ imm('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ imm('LR10',128) }}
    SET LR11 LR10 ;;
    INC LR11 128 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
{{ imm('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(26,19,9)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
{{ coefficient(16,1,10) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
{{ coefficient(94,1,11) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    SET LR2 CR0 ;;
row:
    SET LR4 LR2 ;;
{{ clear() }}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    BEQ LR8 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    SET LR3 CR0 ;;
max_next:
    INC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR3 1 ;;
    BEQ LR3 LR8 max_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ;;
    B max_next ;;
max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX LR0 {{ tail }} ;;
    B max_ready ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    SET LR4 LR2 ;;
{% call(ds) tiles('exp') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for slot in [5,6,8,9] %}
{{ imm('LR5',slot) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
    INC LR4 1 ;;
{% endcall %}

{# Square roots and correct reciprocal using the residual of the sum. #}
{{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ;;
{% endcall %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{{ imm('LR13',128) }}
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR13 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
{{ imm('LR5',7) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

    SET LR4 LR2 ;;
{% call(ds) tiles('normalize') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ;;
    LD.MULT R1 LR3 {{ cr.exps }} ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;
    HALT ;;
