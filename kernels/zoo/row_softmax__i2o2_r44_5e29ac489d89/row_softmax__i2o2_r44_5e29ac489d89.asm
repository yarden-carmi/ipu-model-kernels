{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_formats ~ '.L' %}
{% set work = cr.scratch_formats ~ '.H' %}
{% set full = cr.active ~ '.L' %}
{% macro addr(r,i) %}
    SET {{ r }} CR0 ;;
    INC {{ r }} {{ i }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{# Construct dyadic coefficients without folded tensors. #}
{% macro coefficient(p,c,s) %}
{{ addr('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',p) }}
pow_{{ s }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 pow_{{ s }} ;;
{{ addr('LR1',s) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ addr('LR6',c) }}
num_{{ s }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 num_{{ s }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ addr('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,8),(13,21,9),(19,18,10),(26,19,11)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
{{ coefficient(16,1,12) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
{{ coefficient(94,1,13) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
{{ coefficient(30,1,14) }}
{{ addr('LR11',128) }}
    SET LR12 LR11 ;;
    INC LR12 128 ;;
    SET LR13 LR12 ;;
    INC LR13 128 ;;
    SET LR2 CR0 ;;
batch:
    {# Each lane owns a complete softmax row. Advance by K to visit its columns. #}
    SET LR3 CR0 ; SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    BEQ LR3 LR8 tail_tile ;;
full_tile:
{% macro tile(tag,ds) %}
    ADD LR4 LR2 LR3 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.MAX.FIRST ;;
    SET LR6 LR15 ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 {{ tag }}_max_done ;;
{{ tag }}_max:
    ADD LR4 LR4 {{ cr.K }} ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.MAX ; DEC LR6 1 ;;
    BNE LR6 CR0 {{ tag }}_max ;;
{{ tag }}_max_done:
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR11 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    ADD LR4 LR2 LR3 ; SET LR5 CR0 ;;
{{ tag }}_exp:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
{% for slot in range(8,12) %}
{{ addr('LR1',slot) }}
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR11 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR12 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %} ;;
{% endfor %}
{{ addr('LR1',14) }}
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.VE LR11 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR5 ;;
{{ addr('LR1',12) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR5 {{ cr.roots }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} LR5 ; ADD LR4 LR4 {{ cr.K }} ;;
    INC LR5 1 ;;
    BLT.S LR5 LR15 {{ tag }}_exp ;;

    SET LR5 CR0 ;;
{{ clear() }}
{{ tag }}_sum:
    LD.MULT.CYCLIC LR5 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD ; INC LR5 1 ;;
    BLT.S LR5 LR15 {{ tag }}_sum ;;
{{ addr('LR1',2) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR1 ;;
    ACTIVATE.QUANTIZE reciprocal {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR13 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{# One Newton correction of the quantized reciprocal. #}
{{ addr('LR1',7) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VV LR13 R1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR11 ;;
    ADD LR4 LR2 LR3 ; SET LR5 CR0 ;;
{{ addr('LR1',13) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
{{ tag }}_out:
    LD.MULT.CYCLIC LR5 {{ cr.roots }} LR0 ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR13 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR11 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
    ADD LR4 LR4 {{ cr.K }} ; INC LR5 1 ;;
    BLT.S LR5 LR15 {{ tag }}_out ;;
{% endmacro %}
{{ tile('full',full) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 full_tile ;;
tail_tile:
{{ tile('tail',cr.part ~ '.L') }}
    ADD LR2 LR2 {{ cr.batchstride }} ;;
    BLT.S LR2 {{ cr.M }} batch ;;
    HALT ;;
