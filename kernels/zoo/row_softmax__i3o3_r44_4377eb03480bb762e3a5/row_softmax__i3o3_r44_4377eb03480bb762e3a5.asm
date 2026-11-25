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

{# Generate dyadic coefficients in the input format. #}
{% macro coefficient(power,count,slot) %}
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;
    DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ imm('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;
    DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}

{% macro tiles(label) %}
    SET LR3 CR0 ; SET LR4 LR2 ; BEQ LR8 CR0 {{ label }}_tail ;;
{{ label }}_loop:
{{ caller(full) }}
    INC LR3 1 ; INC LR4 1 ;;
    BLT.S LR3 LR8 {{ label }}_loop ;;
{{ label }}_tail:
{{ caller(tail) }}
{% endmacro %}

    SET LR0 CR0 ;;
{{ imm('LR10',128) }}
    SET LR11 LR10 ;;
    INC LR11 128 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
{{ imm('LR13',128) }}
{{ imm('LR14',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR14 ;;
{% for p,c,s in [(5,23,5),(13,21,6)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
{{ coefficient(16,1,10) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',80) }}
floor_loop:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 floor_loop ;;
{{ imm('LR1',4) }}
    SET LR9 LR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
{{ imm('LR6',5) }}
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ; SET LR2 CR0 ;;

row_loop:
{{ clear() }}
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR4 LR2 ; SET LR3 CR0 ; SET LR1 CR1 ; BEQ LR8 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; INC LR3 1 ; INC LR4 1 ;;
    BEQ LR3 LR8 max_tail ;;
max_loop:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; INC LR3 1 ; INC LR4 1 ;;
    BLT.S LR3 LR8 max_loop ;;
max_tail:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX LR0 {{ tail }} ;;
    B max_ready ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
max_ready:
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;

{# Approximate exp(x-max) as the square of a scaled exp2 root. #}
{% call(ds) tiles('exponent') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
{% for coeff in ['LR0','LR12'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV {{ coeff }} R1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
{% endfor %}
    MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.MAX ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
{% endcall %}

{{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ;;
{% endcall %}

{# Recover the sum residual and use it to correct the reciprocal. #}
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR13 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

{% call(ds) tiles('normalize') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR0 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR0 {{ cr.exps }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row_loop ;;
    HALT ;;
