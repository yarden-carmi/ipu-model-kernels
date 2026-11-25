{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{# Generate a dyadic coefficient from exp2(0), without folded constants. #}
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
    SET LR0 CR0 ;;
{{ imm('LR14',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR14 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(20,1,9),(16,1,10)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
{{ imm('LR8',128) }}
    SET LR9 LR8 ;;
    INC LR9 128 ;;
    SET LR11 LR9 ;;
    INC LR11 128 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR2 CR0 ; SET LR3 CR0 ;;
{{ imm('LR4',3) }}
{{ imm('LR5',4) }}
packed_row:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR9 ; SET LR7 LR9 ;;
    INC LR2 1 ;;
item:
{{ clear() }}
    MULT.RC.VE LR7 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
{# Three terms of log2(e)/2; square after storing a scaled root. #}
{% for slot in [5,6,8] %}
{{ imm('LR6',slot) }}
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.RC.VV LR7 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
{% endfor %}
{# A common downward shift guards exp2 against positive rounding noise at the maximum. #}
{{ imm('LR6',9) }}
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.tmp }} LR4 ;;
    LD.MULT R0 LR4 {{ cr.tmp }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.tmp }} LR4 ;;
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
{{ clear() }}
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM.FIRST LR0 {{ ds }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;

{# Split the sum and use its residual to refine the rounded reciprocal. #}
    LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR8 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR8 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR8 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR8 LR8 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR8 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

{# Split the squared weight too, and multiply both pieces by the corrected reciprocal. #}
    LD.MULT.CYCLIC LR4 {{ cr.tmp }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR5 ;;
    LD.MULT R0 LR5 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.tmp }} LR5 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR8 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR5 {{ cr.tmp }} ;;
    MULT.RC.VV LR8 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
    ADD LR7 LR7 {{ cr.n }} ;;
    BEQ LR3 {{ cr.rows }} done ;;
    BLT.S LR7 {{ cr.packed_end }} item ;;
    B packed_row ;;
done:
    HALT ;;
