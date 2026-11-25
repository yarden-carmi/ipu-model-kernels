{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro imm(reg, value) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ value }} ;;
{% endmacro %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}

{# Synthesize exact dyadic coefficients in the input format where representable. #}
{% macro coefficient(power, count, slot) %}
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6', power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ imm('LR1', slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6', count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}

{# A logical row uses full tiles followed by one nonempty tail tile. #}
{% macro tiles(label) %}
    SET LR3 CR0 ;;
    BEQ LR8 CR0 {{ label }}_tail ;;
{{ label }}_loop:
{{ caller(full) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 {{ label }}_loop ;;
{{ label }}_tail:
{{ caller(tail) }}
{% endmacro %}

    SET LR0 CR0 ;;
{{ imm('LR10', 128) }}
    SET LR11 LR10 ;;
    INC LR11 128 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
{{ imm('LR14', 7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR14 ;;
{{ coefficient(5, 23, 5) }}
{{ coefficient(13, 21, 6) }}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
{{ coefficient(16, 1, 10) }}
    SET LR15 LR1 ;;
    LD.MULT R0 LR14 {{ cr.tmp }} ;;
{{ imm('LR6', 80) }}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB.FIRST ; DEC LR6 1 ;;
floor_loop:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ; DEC LR6 1 ;;
    BNE LR6 CR0 floor_loop ;;
{{ imm('LR1', 4) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    SET LR2 CR0 ; SET LR5 CR0 ; SET LR13 CR0 ;;

row:
{# LR2 addresses a packed group, and LR5 selects its logical row in lanes.
   Only the first ds lanes of the rotated cyclic window are ever stored/reduced. #}
{{ clear() }}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR5 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
{% call(ds) tiles('maximum') %}
    ADD LR4 LR2 LR3 ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR5 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX LR0 {{ ds }} ;;
{% endcall %}
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{{ imm('LR6', 5) }}
{{ imm('LR9', 6) }}
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR10 ;;

{% call(ds) tiles('exponent') %}
    ADD LR4 LR2 LR3 ;;
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.RC.VV LR5 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.RC.VV LR5 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VV LR12 R1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR15 {{ cr.tmp }} ;;
    {# A common negative bias keeps exact ties in the exp2 table's domain. #}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VE LR11 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.MAX ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ;;
{% endcall %}

{{ clear() }}
{% call(ds) tiles('sum') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ;;
{% endcall %}

{# Recover the sum's quantization residual and refine its reciprocal. #}
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ; INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR10 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR10 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

{% call(ds) tiles('normalize') %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ;;
    LD.MULT R0 LR3 {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} LR3 ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.exps }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ADD LR7 LR13 LR3 ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR7 ;;
{% endcall %}
    ADD LR13 LR13 {{ cr.K }} ;;
    ADD LR5 LR5 {{ cr.n }} ;;
    BLT.S LR5 {{ cr.extent }} next_row ;;
    SET LR5 CR0 ; ADD LR2 LR2 {{ cr.K }} ;;
next_row:
    BLT.S LR13 {{ cr.M }} row ;;
    HALT ;;
