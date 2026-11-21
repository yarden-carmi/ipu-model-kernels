{% set q = cr.qf_in0 ~ '.L' %}
{% set full = cr.active ~ '.L' %}
{% set part = cr.part ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro addr(reg, value) %}
    SET {{ reg }} CR0 ;;
{% if value %}
    INC {{ reg }} {{ value }} ;;
{% endif %}
{% endmacro %}
{% macro tiles(label) %}
    SET LR7 CR0 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    BEQ LR7 LR8 {{ label }}_tail ;;
{{ label }}_full:
{{ caller(full) }}
    INC LR7 1 ;;
    BLT.S LR7 LR8 {{ label }}_full ;;
{{ label }}_tail:
{{ caller(part) }}
{% endmacro %}
    SET LR0 CR0 ;;
{{ addr('LR11',128) }}
    SET LR9 CR0 ;;
    SET LR10 LR11 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
    SET LR13 LR12 ;;
    INC LR13 128 ;;

{# Generate 1 and a split log2(e)/2. #}
{{ addr('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% macro coefficient(power, numerator, row) %}
{{ addr('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',power) }}
power_{{ row }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ row }} ;;
{{ addr('LR1',row) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',numerator) }}
numerator_{{ row }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 numerator_{{ row }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
{% for p,k,r in [(5,23,5),(13,21,6),(19,18,8),(26,19,9)] %}
{{ coefficient(p,k,r) }}
{% endfor %}
{# Keep squared numerators scaled up by 2^32 across the scratch store. #}
{{ coefficient(16,1,10) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
{# Round scaled subnormal numerators to the FP32 exp grid. #}
{{ coefficient(94,1,11) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR13 ;;
    SET LR2 CR0 ;;
row:
    SET LR4 LR2 ;;
{{ clear() }}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    SET LR7 CR1 ;;
    SET LR8 {{ cr.K }} ;;
    BEQ LR7 LR8 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
max_next:
    INC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    INC LR7 1 ;;
    BEQ LR7 LR8 max_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ;;
    B max_next ;;
max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ part }} {{ q }} ; AGG.MAX LR0 {{ part }} ;;
    B max_ready ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ part }} {{ q }} ; AGG.MAX.FIRST LR0 {{ part }} ;;
max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    SET LR4 LR2 ;;
    SET LR3 CR0 ;;
{% call(ds) tiles('exp') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for idx in [5,6,8,9] %}
{{ addr('LR5',idx) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR9 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ q }} {{ cr.roots }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.roots }} LR3 ;;
    INC LR4 1 ;;
    INC LR3 1 ;;
{% endcall %}
    SET LR3 CR0 ;;
{{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ q }} ; AGG.SUM LR0 {{ ds }} ;;
    INC LR3 1 ;;
{% endcall %}
{# Carry the sum as two quantized pieces into a broadcast reciprocal. #}
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.EE LR11 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
{# Refine the rounded reciprocal with r + r * (1 - sum * r). #}
    SET LR1 CR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{{ addr('LR5',7) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR9 ;;
    MULT.RC.VE LR9 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR11 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    INC LR1 2 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% call(ds) tiles('output') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR9 ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VS LR9 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.exps }} LR3 ;;
    LD.MULT R1 LR3 {{ cr.exps }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VV LR9 R1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR3 1 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;
    HALT ;;
