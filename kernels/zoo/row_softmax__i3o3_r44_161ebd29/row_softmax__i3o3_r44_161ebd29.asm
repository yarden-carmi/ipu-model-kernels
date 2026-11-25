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

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
{{ imm('LR10',128) }}
    ADD LR11 LR10 LR10 ; SET LR5 LR10 ;;
    ADD LR12 LR11 LR10 ;;
{{ imm('LR14',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR14 ;;
{# Approximate log2(e)/2 with two dyadic terms. #}
{{ coefficient(5,23,5) }}
{{ coefficient(13,21,6) }}
{{ coefficient(16,1,10) }}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
{{ imm('LR15',5) }}
{{ imm('LR13',6) }}
{{ imm('LR9',10) }}

{# LR2: input tile base; LR5: cyclic index of this logical row's first lane.
   LR7: output tile base. Tile scans handle the last tile with its own DS. #}
{% macro scan(label) %}
    SET LR3 CR0 ; BEQ LR8 CR0 {{ label }}_tail ;;
{{ label }}_full:
{{ caller(full, false) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 {{ label }}_full ;;
{{ label }}_tail:
{{ caller(tail, true) }}
{% endmacro %}
{% macro maximum(ds, first) %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR10 ;;
    MULT.RC.VE LR5 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; INC LR4 1 ;;
{% endmacro %}
row:
{{ clear() }}
    SET LR4 LR2 ; BEQ LR8 CR0 max_single ;;
{{ maximum(full,true) }}
    SET LR3 CR1 ; BEQ LR3 LR8 max_tail ;;
max_full:
{{ maximum(full,false) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 max_full ;;
max_tail:
{{ maximum(tail,false) }}
    B max_ready ;;
max_single:
{{ maximum(tail,true) }}
max_ready:
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ; SET LR4 LR2 ;;

{% call(ds,last) scan('exp') %}
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR10 ;;
{% for coeff in ['LR15','LR13'] %}
    LD.MULT R0 {{ coeff }} {{ cr.tmp }} ;;
    LD.MULT.CYCLIC {{ coeff }} {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR5 LR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE LR0 LR10 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; LD.MULT R0 LR9 {{ cr.tmp }}{% endif %} ;;
{% endfor %}
    {# Uniform negative guard for rounding near zero (cancels on normalization). #}
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ; INC LR4 1 ;;
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
{% endcall %}

{{ clear() }}
{% call(ds,last) scan('sum') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }}{% if last %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0{% endif %} ;;
{% endcall %}

{# Split the sum and the reciprocal into leading and residual terms. #}
    SET LR1 CR1 ; LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
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

    SET LR4 LR7 ;;
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
    SET LR7 LR4 ; BEQ LR4 {{ cr.M }} finished ;;
    ADD LR5 LR5 {{ cr.shift_step }} ;;
    BLT.S LR5 {{ cr.shift_end }} row ;;
    SET LR5 LR10 ;;
next_input:
    ADD LR2 LR2 {{ cr.K }} ; B row ;;
finished:
    HALT ;;
