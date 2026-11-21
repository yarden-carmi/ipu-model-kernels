{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set qr = cr.rootq ~ '.L' %}
{% set full = cr.active ~ '.L' %}
{% set part = cr.part ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro addr(reg, value) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ value }} ;;
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

{# Construct the split coefficients of log2(e)/2 without folded tensors. #}
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
{# Scale the squared numerators by 2^32; retain the FP32 subnormal grid. #}
{{ coefficient(16,1,10) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ qr }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
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
{% call(ds) tiles('exponentiate') %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for idx in [5,6,8,9] %}
{{ addr('LR5',idx) }}
    LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR9 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ qr }} {{ cr.roots }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ qr }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qr }} {{ cr.roots }} LR3 ;;
    INC LR4 1 ;;
    INC LR3 1 ;;
{% endcall %}
    SET LR3 CR0 ;;
{{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR9 ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ qr }} ; AGG.SUM LR0 {{ ds }} ;;
    INC LR3 1 ;;
{% endcall %}
{# Recombine the rounded sum and its residual before taking the reciprocal. #}
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
    SET LR3 CR0 ;;
    SET LR4 LR2 ;;
{% call(ds) tiles('normalize') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR9 ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VS LR9 0 LR0 {{ ds }} {{ qr }} ; ACC.ADD ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    SET LR5 LR3 ;;
    INC LR5 12 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R1 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.norm }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.SUB ;;
    ADD LR5 LR4 {{ cr.M }} ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.norm }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.norm }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.SUB ;;
    ADD LR5 LR5 {{ cr.M }} ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.norm }} LR5 ;;
    INC LR3 1 ;;
    INC LR4 1 ;;
{% endcall %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} row ;;

{# Gather normalized columns into output tiles. #}
    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
{{ addr('LR7',128) }}
transpose_batch:
    SET LR5 CR0 ;;
    SET LR10 CR0 ;;
    SET LR11 CR0 ;;
transpose_column:
    ADD LR4 LR2 LR11 ;;
    SET LR8 CR0 ;;
{% macro store(ds) %}
    SET LR6 CR1 ;;
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.ADD ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
transpose_tile:
    SET LR9 LR4 ;;
    SET LR1 CR0 ;;
gather:
    SET LR12 CR0 ;;
    SET LR13 CR0 ;;
{{ clear() }}
transpose_lane:
    LD.MULT R0 LR4 {{ cr.norm }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ qo }} ; ACC.RESHAPE LRD12 LRD12 7 ;;
    ADD LR4 LR4 {{ cr.K }} ;;
    INC LR1 1 ;;
    ADD LR6 LR8 LR1 ;;
    BEQ LR6 LR14 gathered ;;
    ADDBI LRD12 1 ;;
    BLT.S LR1 LR7 transpose_lane ;;
gathered:
    BLT.S LR9 {{ cr.M }} gather_high ;;
    SUB LR6 LR9 {{ cr.M }} ;;
    BGE.S LR6 {{ cr.M }} gather_finish ;;
    SET LR6 CR1 ;;
    B gather_save ;;
gather_high:
    SET LR6 CR0 ;;
gather_save:
    ACTIVATE.QUANTIZE identity {{ full }} {{ qo }} {{ cr.tmp }} LR6 ;;
    ADD LR9 LR9 {{ cr.M }} ;;
    SET LR4 LR9 ;;
    SET LR1 CR0 ;;
    B gather ;;
gather_finish:
    SUB LR4 LR4 {{ cr.M }} ;;
    SUB LR4 LR4 {{ cr.M }} ;;
    ADD LR8 LR8 LR1 ;;
    BEQ LR8 LR14 transpose_tail ;;
{{ store(full) }}
    B transpose_tile ;;
transpose_tail:
{{ store(cr.outpart ~ '.L') }}
    INC LR5 1 ;;
    BEQ LR5 LR15 transpose_next ;;
    INC LR10 1 ;;
    BNE LR10 LR7 transpose_column ;;
    SET LR10 CR0 ;;
    INC LR11 1 ;;
    B transpose_column ;;
transpose_next:
    ADD LR2 LR2 {{ cr.batchstride }} ;;
    BLT.S LR2 {{ cr.M }} transpose_batch ;;
    HALT ;;
