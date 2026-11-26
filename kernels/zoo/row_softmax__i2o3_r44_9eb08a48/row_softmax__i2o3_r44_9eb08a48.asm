{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set scalar = cr.full ~ '.H' %}
{% set tail = cr.tail ~ '.L' %}
{% set root = cr.scratch_formats ~ '.L' %}
{% set work = cr.scratch_formats ~ '.H' %}
{% macro imm(r,v) %}
    SET {{ r }} CR0 ;;
    INC {{ r }} {{ v }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro coeff(p,c,s) %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR1',p) }}
pow_{{ s }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR1 1 ;;
    BNE LR1 CR0 pow_{{ s }} ;;
{{ imm('LR2',s) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR2 ;;
    LD.MULT R0 LR2 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR1',c) }}
num_{{ s }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR1 1 ;;
    BNE LR1 CR0 num_{{ s }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR2 ;;
{% endmacro %}
{% macro tiles(tag) %}
    SET LR1 CR0 ; BEQ LR14 CR0 {{ tag }}_tail ;;
{{ tag }}_full:
{{ caller(full) }}
    INC LR1 1 ;;
    BLT.S LR1 LR14 {{ tag }}_full ;;
{{ tag }}_tail:
{{ caller(tail) }}
{% endmacro %}

    SET LR0 CR0 ;;
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
{% for p,c,s in [(5,23,1),(13,21,2),(3,1,7)] %}
{{ coeff(p,c,s) }}
{% endfor %}
    SET LR11 CR0 ; SET LR12 CR0 ;;
    SET LR13 CR0 ; DEC LR14 1 ;;

{# LR11 is the query index; LR12 is the base of its contiguous plane.
   Gather across columns, advancing by one padded dim-2 pitch each time. #}
row:
    SET LR1 CR0 ; SET LR2 LR11 ;;
lane_mod:
    SET LR3 LR2 ;;
    DEC LR3 128 ;;
    BLT.S LR3 LR0 lane_ready ;;
    INC LR1 1 ; SET LR2 LR3 ; B lane_mod ;;
lane_ready:
    ADD LR4 LR12 LR1 ;;
{{ imm('LR3',128) }}
{% call(ds) tiles('gather') %}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR5 {{ 'LR3' if ds == full else 'LR15' }} ;;
gather_loop_{{ 'full' if ds == full else 'tail' }}:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR2 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD8 7 ; DEC LR5 1 ; ADD LR4 LR4 {{ cr.pitch }} ;;
    ADDBI LRD8 1 ; BNE LR5 CR0 gather_loop_{{ 'full' if ds == full else 'tail' }} ;;
    {# Store a residual to preserve precision after gathering across scales. #}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tiles }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tiles }} ; ADD LR6 LR1 LR14 ;;
    INC LR6 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.tiles }} LR6 ;;
{% endcall %}

{% call(ds) tiles('maximum') %}
    LD.MULT R0 LR1 {{ cr.tiles }} ; BEQ LR1 CR0 first_{{ 'full' if ds == full else 'tail' }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX LR0 {{ ds }} ; B next_{{ 'full' if ds == full else 'tail' }} ;;
first_{{ 'full' if ds == full else 'tail' }}:
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX.FIRST LR0 {{ ds }} ;;
next_{{ 'full' if ds == full else 'tail' }}:
{% endcall %}
{{ imm('LR5',3) }}
    ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR5 ;;
    LD.MULT R1 LR5 {{ cr.tmp }} ;;
{% call(ds) tiles('exponent') %}
    LD.MULT R0 LR1 {{ cr.tiles }} ; SET LR2 CR1 ;;
{% for slot in range(2) %}
    LD.MULT.CYCLIC LR2 {{ cr.tmp }} LR0 ;;
    INC LR2 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
{% endfor %}
    ADD LR2 LR1 LR14 ;;
    INC LR2 1 ;;
    LD.MULT R0 LR2 {{ cr.tiles }} ; SET LR2 CR1 ;;
{% for slot in range(2) %}
    LD.MULT.CYCLIC LR2 {{ cr.tmp }} LR0 ;;
    INC LR2 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
{% endfor %}
{{ imm('LR2',7) }}
    LD.MULT R0 LR2 {{ cr.tmp }} ; SET LR2 LR1 ;;
{% for phase in range(4) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.tiles }} LR2 ;;
{% if not loop.last %}
    ADD LR2 LR2 LR14 ;;
    INC LR2 1 ;;
{% endif %}
{% endfor %}
{% endcall %}

{# Sum squared root estimates at staggered table phases. #}
{% macro weights(ds,reduce) %}
    SET LR2 LR1 ;;
{% for phase in range(4) %}
    LD.MULT.CYCLIC LR2 {{ cr.tiles }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; {% if reduce %}AGG.SUM LR0 {{ ds }}{% else %}ACC.ADD{% if loop.first %}.FIRST{% endif %}{% endif %} ;;
{% if not loop.last %}
    ADD LR2 LR2 LR14 ;;
    INC LR2 1 ;;
{% endif %}
{% endfor %}
{% endmacro %}
{{ clear() }}
{% call(ds) tiles('sum') %}
{{ weights(ds,true) }}
{% endcall %}

{# Split the denominator and refine the rounded reciprocal. #}
{{ imm('LR5',4) }}
{{ imm('LR6',5) }}
{{ imm('LR7',6) }}
{{ imm('LR8',128) }}
    ADD LR9 LR8 LR8 ;;
    ACTIVATE.QUANTIZE identity {{ scalar }} {{ work }} {{ cr.tmp }} LR5 ;;
    ACTIVATE.QUANTIZE reciprocal {{ scalar }} {{ work }} {{ cr.tmp }} LR6 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ work }} {{ cr.tmp }} LR7 ;;
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR6 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR8 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    LD.MULT R1 LR7 {{ cr.tmp }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR8 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VV LR8 R1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ work }} {{ cr.tmp }} LR7 ;;
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.RC.VE LR8 LR0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR9 ;;
    MULT.RC.VE LR9 LR0 0 LR0 {{ full }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR7 ;;
    LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR9 ;;

{% call(ds) tiles('normalize') %}
{{ weights(ds,false) }}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR7 ;;
    LD.MULT R1 LR7 {{ cr.tmp }} ;;
    MULT.RC.VV LR8 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR8 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR9 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR9 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endcall %}
    INC LR11 1 ; BEQ LR13 {{ cr.end }} done ;;
    BLT.S LR11 {{ cr.in0_d2 }} row ;;
    SET LR11 CR0 ; ADD LR12 LR12 {{ cr.plane }} ; B row ;;
done:
    HALT ;;
