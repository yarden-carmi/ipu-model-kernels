{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro coefficient(power,count,slot) %}
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ imm('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ;;
{{ imm('LR10',128) }}
    ADD LR11 LR10 LR10 ;;
    ADD LR15 LR11 LR10 ; SET LR12 CR0 ;;
{{ imm('LR14',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR14 ;;
{# Approximate log2(e)/2 with two dyadic terms. #}
{{ coefficient(5,23,5) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{{ coefficient(13,21,6) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR15 ;;
{{ coefficient(16,1,10) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;

{# LR2: logical row's first tile; LR4: current memory tile. #}
{% macro scan(label) %}
    SET LR4 LR2 ; SET LR3 CR0 ;;
    BEQ LR8 CR0 {{ label }}_tail ;;
{{ label }}_full:
{{ caller(full, false) }}
    INC LR3 1 ; BLT.S LR3 LR8 {{ label }}_full ;;
{{ label }}_tail:
{{ caller(tail, true) }}
{% endmacro %}
{% macro maximum(ds,first) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR4 1 ;;
{% endmacro %}

row:
{{ imm('LR6',5) }}
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
{{ clear() }}
    SET LR4 LR2 ; BEQ LR8 CR0 max_single ;;
{{ maximum(full,true) }}
    SET LR3 CR1 ; BEQ LR3 LR8 max_tail ;;
max_full:
{{ maximum(full,false) }}
    INC LR3 1 ; BLT.S LR3 LR8 max_full ;;
max_tail:
{{ maximum(tail,false) }}
    B max_ready ;;
max_single:
{{ maximum(tail,true) }}
max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;

{% call(ds,last) scan('exp') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
{% for coeff in ['LR0','LR15'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV {{ coeff }} R1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ; INC LR4 1{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
{% endcall %}

{{ clear() }}
{% call(ds,last) scan('sum') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }}{% if last %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0{% endif %} ;;
{% endcall %}

{# Split the sum and refine its reciprocal with the rounding residual. #}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR12 ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR10 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

{% call(ds,last) scan('emit') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR12 ;;
    MULT.RC.VS LR12 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.exps }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR12 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;
    HALT ;;
