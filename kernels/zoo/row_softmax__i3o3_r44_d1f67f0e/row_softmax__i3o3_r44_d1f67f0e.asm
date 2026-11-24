{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% macro imm(reg, val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{# Generate dyadic terms for log2(e)/2 and the internal scaling factors. #}
{% macro coefficient(power, count, slot) %}
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6', power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ imm('LR1', slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% if count != 1 %}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6', count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ;;
{{ imm('LR14', 7) }}
{{ imm('LR10', 128) }}
    ADD LR11 LR10 LR10 ;;
    ADD LR12 LR11 LR10 ;;
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR14 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,17,8),(26,109,9)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
{% for p,s,fun,index in [(16,10,'reciprocal','LR11'),(94,11,'identity','LR12')] %}
{{ coefficient(p,1,s) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ fun }} {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} {{ index }} ;;
{% endfor %}
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;

{# LR2 is the packed memory row, LR3 the output row, LR4 the packed lane offset. #}
row:
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR1 CR1 ;;
    MULT.VE LR4 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR10 ;;
    ADD LR7 LR10 LR4 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
{# A tiny negative guard covers subnormal roundoff at the exp2 domain boundary. #}
{{ imm('LR5', 9) }}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB.FIRST ;;
{{ imm('LR5', 5) }}
{% for slot in [5,6,8,9] %}
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if not loop.last %} ; INC LR5 {{ 2 if slot == 6 else 1 }}{% endif %} ;;
    MULT.RC.VV LR7 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.root }} LR0{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR0 {{ cr.root }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.root }} LR0 ;;

{# Keep the sum's quantization residual for a first-order reciprocal correction. #}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.root }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; INC LR1 1 ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR0 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR10 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

{# Split the squared numerator and combine both parts with both reciprocal terms. #}
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.root }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.exp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exp }} LR0 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR0 {{ cr.exp }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    BGE.S LR3 {{ cr.rows }} done ;;
    BEQ LR4 CR0 second ;;
    SET LR4 CR0 ; INC LR2 1 ; B row ;;
second:
    SET LR4 {{ cr.n }} ; B row ;;
done:
    HALT ;;
