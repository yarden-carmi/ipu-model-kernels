{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set seed_q = cr.full ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{# Generate the dyadic coefficients without folded constants. #}
{% macro coefficient(power,count,slot) %}
{{ imm('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{% if power %}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ seed_q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{% endif %}
{{ imm('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ seed_q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ seed_q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ imm('LR13',128) }}
    SET LR11 LR13 ;;
    INC LR11 128 ;;
{{ imm('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ seed_q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(26,19,9),(16,1,10),(2,1,12),(10,1,13),(0,80,11)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    SET LR8 {{ cr.K }} ; SET LR2 CR0 ;;
    DEC LR8 1 ;;

{# Combine staggered exp2 quantizations in a wide accumulator. #}
{% macro weights(ds,first=false,loop_tag=none) %}
    LD.MULT.CYCLIC LR5 {{ cr.roots }} LR0 ; SET LR6 LR5 ;;
{% for phase in range(4) %}
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% if not loop.last %} ; LD.MULT.CYCLIC LR6 {{ cr.roots }} LR0 ; ADD LR6 LR6 LR15{% elif loop_tag %} ; BLT.S LR5 LR15 {{ loop_tag }}{% endif %}{% if loop.first and loop_tag %} ; INC LR5 1{% endif %} ;;
{% endfor %}
{% endmacro %}

{# One softmax per active lane; successive columns are K memory rows apart. #}
{% macro tile(tag,ds) %}
{{ imm('LR1',11) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ; ADD LR9 LR2 LR3 ;;
    SET LR4 LR9 ; SET LR5 CR0 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.MAX.FIRST ; ADD LR4 LR4 {{ cr.K }} ; BEQ LR5 LR15 {{ tag }}_max_done ;;
{{ tag }}_max:
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR5 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.MAX ; ADD LR4 LR4 {{ cr.K }} ; BLT.S LR5 LR15 {{ tag }}_max ;;
{{ tag }}_max_done:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.VE LR13 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tmp }} LR0 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ; SUB LR4 LR9 {{ cr.K }} ; SET LR5 CR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR13 ;;
{{ imm('LR14',5) }}
{{ imm('LR1',12) }}
{# Keep the quantized maximum and its residual resident while streaming
   the four slope terms through R1 and the input through R0. #}
{{ tag }}_exp:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ; SET LR7 LR14 ; ADD LR4 LR4 {{ cr.K }} ;;
{% for slot in [5,6,8,9] %}
{% if loop.first %}
    LD.MULT R1 LR7 {{ cr.tmp }} ;;
{% endif %}
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR12 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ;;
    MULT.RC.VV LR13 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD{% else %}SUB{% endif %} ; LD.MULT {% if loop.last %}R0{% else %}R1{% endif %} LR7 {{ cr.tmp }} ; INC LR7 {{ 2 if slot == 6 else 1 }} ;;
{% endfor %}
    MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.MAX ; SET LR6 LR5 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR5 ; LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% for phase in range(3) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR6 ; ADD LR6 LR6 LR15{% if loop.first %} ; INC LR5 1{% elif loop.last %} ; BLT.S LR5 LR15 {{ tag }}_exp{% endif %} ;;
{% endfor %}

    SET LR5 CR0 ;;
{{ clear() }}
{{ tag }}_sum:
{{ weights(ds,loop_tag=tag ~ '_sum') }}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR1 ;;
    ACTIVATE.QUANTIZE reciprocal {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR13 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
{{ imm('LR1',7) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ seed_q }} ; ACC.ADD.FIRST ;;
{{ imm('LR1',13) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VV LR13 R1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR12 ;;
    SET LR4 LR9 ; SET LR5 CR0 ;;
{{ tag }}_out:
{{ weights(ds,true) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR13 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR12 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.VE LR0 CR0 0 LR0 {{ ds }} {{ work }} ; ACC.MAX ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
    ADD LR4 LR4 {{ cr.K }} ; INC LR5 1 ;;
    BLT.S LR5 LR15 {{ tag }}_out ;;
{% endmacro %}
batch:
    SET LR3 CR0 ; BEQ LR8 CR0 tail_tile ;;
full_tile:
{{ tile('full',full) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 full_tile ;;
tail_tile:
{{ tile('tail',tail) }}
    ADD LR2 LR2 {{ cr.row_group }} ;;
    BLT.S LR2 {{ cr.M }} batch ;;
    HALT ;;
