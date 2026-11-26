{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set scalar = cr.full ~ '.H' %}
{% set valid = cr.valid ~ '.L' %}
{% macro imm(reg, value) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ value }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{# Build 23/32 + 21/8192, a split approximation of log2(e)/2. #}
{% macro coefficient(power, count, slot) %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6', power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} {{ slot }} ;;
    LD.MULT R0 {{ slot }} {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6', count) }}
sum_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 sum_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ slot }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR1 ; SET LR2 CR0 ;;
{{ imm('LR3', 2) }}
{{ imm('LR4', 3) }}
{{ imm('LR5', 4) }}
{{ imm('LR13', 128) }}
    ADD LR12 LR13 LR13 ;;
    ADD LR11 LR12 LR13 ;;
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
{{ coefficient(5, 23, 'LR1') }}
{{ coefficient(13, 21, 'LR3') }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
    LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR11 ;;
    DEC LR2 1 ; SET LR7 CR0 ;;
packed_row:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; SET LR8 {{ cr.pack }} ; SET LR9 CR0 ;;
    INC LR7 1 ;;
logical_row:
    MULT.RC.VE LR9 CR1 0 LR0 {{ valid }} {{ q }} ; AGG.MAX.FIRST LR0 {{ valid }} ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR4 ;;
    LD.MULT R1 LR4 {{ cr.tmp }} ;;
{% for coeff in ['LR13', 'LR11'] %}
    LD.MULT R0 {{ 'LR1' if loop.first else 'LR3' }} {{ cr.tmp }} ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ valid }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR13 0 LR0 {{ valid }} {{ q }} ; ACC.SUB ;;
{% endfor %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ valid }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE exp2 {{ valid }} {{ root }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR12 ;;
    MULT.RC.VS LR12 0 LR0 {{ valid }} {{ root }} ; AGG.SUM.FIRST LR0 {{ valid }} ; ACTIVATE.QUANTIZE rsqrt {{ scalar }} {{ root }} {{ cr.tmp }} LR4 ;;
    LD.MULT R1 LR4 {{ cr.tmp }} ;;
    MULT.RC.VE LR12 LR13 0 LR0 {{ valid }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ valid }} {{ root }} {{ cr.tmp }} LR5 ;;
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR12 ; INC LR2 1 ;;
    MULT.RC.VS LR12 0 LR0 {{ valid }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ valid }} {{ qo }} {{ cr.out0 }} LR2 ; DEC LR8 1 ; ADD LR9 LR9 {{ cr.n }} ;;
    ADD LR10 LR2 CR1 ;;
    BEQ LR10 {{ cr.rows }} done ;;
    BNE LR8 CR0 logical_row ;;
    B packed_row ;;
done:
    HALT ;;
