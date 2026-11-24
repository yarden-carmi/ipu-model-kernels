{% set full = cr.full ~ '.L' %}
{% set scalar = cr.full ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set q = cr.logit_root ~ '.L' %}
{% set root = cr.logit_root ~ '.H' %}
{% set work = cr.work ~ '.L' %}
{% macro imm(r,v) %}
    SET {{ r }} CR0 ;;
    INC {{ r }} {{ v }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro coeff(power,num,slot) %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR1',power) }}
pow_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR1 1 ;;
    BNE LR1 CR0 pow_{{ slot }} ;;
{{ imm('LR2',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR2 ;;
    LD.MULT R0 LR2 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR1',num) }}
num_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR1 1 ;;
    BNE LR1 CR0 num_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR2 ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
{# Approximate log2(e)/2 with three exactly representable dyadic terms. #}
{% for p,c,s in [(5,23,1),(13,21,2),(19,18,3)] %}
{{ coeff(p,c,s) }}
{% endfor %}
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    SET LR13 CR0 ; DEC LR14 1 ;;
{# LR10: flattened output row, LR11: row in head, LR12: input head base,
   LR13: next output memory row. Each gather walks dim 3 at a tile stride. #}
row:
    SET LR1 CR0 ; SET LR2 LR11 ;;
lane_mod:
    SET LR3 LR2 ;;
    DEC LR3 128 ;;
    BLT.S LR3 LR0 lane_ready ;;
    INC LR1 1 ; SET LR2 LR3 ;;
    B lane_mod ;;
lane_ready:
    ADD LR4 LR12 LR1 ; SET LR1 CR0 ;;
{% macro gather(tag,ds,count) %}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR5 {{ count }} ;;
gather_{{ tag }}:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR2 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD6 LRD8 7 ; DEC LR5 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    ADDBI LRD8 1 ; BNE LR5 CR0 gather_{{ tag }} ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tiles }} LR1 ;;
{% endmacro %}
    BEQ LR14 CR0 gather_tail_entry ;;
    SET LR3 CR0 ; INC LR3 128 ;;
gather_full_entry:
{{ gather('full',full,'LR3') }}
    INC LR1 1 ;;
    BLT.S LR1 LR14 gather_full_entry ;;
gather_tail_entry:
{{ gather('tail',tail,'LR15') }}

    SET LR1 CR0 ;;
    LD.MULT R0 LR1 {{ cr.tiles }} ;;
    BEQ LR14 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    INC LR1 1 ;;
max_next:
    LD.MULT R0 LR1 {{ cr.tiles }} ;;
    BEQ LR1 LR14 max_tail ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; INC LR1 1 ; B max_next ;;
max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX LR0 {{ tail }} ; B max_done ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
max_done:
{{ imm('LR5',4) }}
    ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R1 LR5 {{ cr.tmp }} ; SET LR1 CR0 ;;
{{ imm('LR8',128) }}
{% macro per_tile(tag) %}
    BEQ LR1 LR14 {{ tag }}_tail ;;
{{ tag }}_full:
{{ caller(full) }}
    INC LR1 1 ;;
    BLT.S LR1 LR14 {{ tag }}_full ;;
{{ tag }}_tail:
{{ caller(tail) }}
{% endmacro %}
{% call(ds) per_tile('exp') %}
    LD.MULT R0 LR1 {{ cr.tiles }} ; SET LR2 CR1 ;;
{% for slot in range(3) %}
    LD.MULT.CYCLIC LR2 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ; INC LR2 1 ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
{% endfor %}
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.tiles }} LR1 ;;
{% endcall %}

    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{{ clear() }}
    SET LR1 CR0 ;;
{% call(ds) per_tile('sum') %}
    LD.MULT.CYCLIC LR1 {{ cr.tiles }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ;;
{% endcall %}
{# Preserve both the rounded reciprocal and its first-order correction. #}
{{ imm('LR5',4) }}
{{ imm('LR6',5) }}
{{ imm('LR7',6) }}
{{ imm('LR8',128) }}
    ACTIVATE.QUANTIZE identity {{ scalar }} {{ work }} {{ cr.tmp }} LR5 ;;
    ACTIVATE.QUANTIZE reciprocal {{ scalar }} {{ work }} {{ cr.tmp }} LR6 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ work }} {{ cr.tmp }} LR7 ;;
    LD.MULT R1 LR7 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR8 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR6 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR8 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.VE LR8 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR8 R0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.RC.VV LR8 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR7 ;;
    INC LR8 128 ;;
    LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR8 ; SET LR1 CR0 ;;
    DEC LR8 128 ;;
{% call(ds) per_tile('output') %}
    LD.MULT.CYCLIC LR1 {{ cr.tiles }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ; SET LR9 LR8 ;;
    INC LR9 128 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR5 ;;
    LD.MULT R1 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR8 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR8 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR9 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endcall %}
    INC LR10 1 ; INC LR11 1 ;;
    BEQ LR10 {{ cr.rows }} done ;;
    BLT.S LR11 {{ cr.in0_d2 }} row ;;
    SET LR11 CR0 ; ADD LR12 LR12 {{ cr.group }} ; B row ;;
done:
    HALT ;;
