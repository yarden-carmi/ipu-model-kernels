{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set work = cr.scratch_qf ~ '.H' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro imm(reg,val) %}
    SET {{ reg }} CR0 ;;
    INC {{ reg }} {{ val }} ;;
{% endmacro %}
{% macro tiles(label, paired) %}
{% if paired %}
    SET LR3 CR0 ;;
{{ caller(full) }}
    INC LR3 1 ;;
{{ caller(full) }}
{% else %}
    SET LR3 CR0 ;;
    BEQ LR3 LR8 {{ label }}_tail ;;
{{ label }}_loop:
{{ caller(full) }}
    INC LR3 1 ;;
    BLT.S LR3 LR8 {{ label }}_loop ;;
{{ label }}_tail:
{{ caller(tail) }}
{% endif %}
{% endmacro %}

{# Generate dyadic coefficients without folded constants. #}
{% macro coefficient(power,count,slot) %}
{{ imm('LR1',7) }}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',power) }}
power_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 power_{{ slot }} ;;
{{ imm('LR1',slot) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{{ clear() }}
{{ imm('LR6',count) }}
count_{{ slot }}:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ;;
    DEC LR6 1 ;;
    BNE LR6 CR0 count_{{ slot }} ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
{{ imm('LR10',128) }}
    SET LR11 LR10 ;;
    INC LR11 128 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
{{ imm('LR1',7) }}
{{ clear() }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% for p,c,s in [(5,23,5),(13,21,6),(19,18,8),(26,19,9)] %}
{{ coefficient(p,c,s) }}
{% endfor %}
{{ coefficient(16,1,10) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
{{ coefficient(94,1,11) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    SUB LR7 LR8 CR1 ;;
    SET LR2 CR0 ;;
{{ imm('LR13',128) }}
{{ imm('LR14',7) }}
    BEQ LR11 {{ cr.n }} pair_setup ;;
{% macro process(label, paired) %}
{% if paired %}
pair_setup:
{{ imm('LR6',5) }}
{{ imm('LR5',6) }}
{% endif %}
{{ label }}_row:
{% if paired %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR4 LR2 CR1 ; SET LR3 CR0 ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% else %}
    SET LR4 LR2 ;;
{{ clear() }}
    ADD LR9 LR2 LR8 ; DEC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; DEC LR9 1 ; BEQ LR8 CR0 {{ label }}_max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BEQ LR4 LR9 {{ label }}_max_tail ;;
{{ label }}_max_next:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BLT.S LR4 LR9 {{ label }}_max_next ;;
{{ label }}_max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX LR0 {{ tail }} ;;
    B {{ label }}_max_ready ;;
{{ label }}_max_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
{{ label }}_max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% endif %}
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
{% if paired %}
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% else %}
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; SET LR4 LR2 ;;
    SET LR3 CR0 ; SET LR6 CR0 ; SET LR5 CR0 ;;
    INC LR6 5 ; INC LR5 6 ; DEC LR4 1 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
{% endif %}
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% macro exponent(ds, pair_tile=-1, next_label='') %}
{% for slot in [5,6,8,9] %}
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}SUB{% else %}ADD{% endif %}{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ q }} ; ACC.{% if loop.last %}ADD ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ; DEC LR5 3{% else %}SUB ; LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0{% if slot != 5 %} ; INC LR5 {{ 2 if slot == 6 else 1 }}{% endif %}{% endif %} ;;
{% endfor %}
    LD.MULT R0 LR3 {{ cr.roots }}{% if next_label %} ; SET LR9 LR3{% endif %} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} {{ 'LR9' if next_label else 'LR3' }}{% if pair_tile == 1 %} ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0{% elif next_label %} ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; INC LR3 1 ; BLT.S LR3 LR7 {{ next_label }}{% endif %} ;;
{% if pair_tile == 0 %}
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR3 1 ;;
{% endif %}
{% endmacro %}
{% if paired %}
{# Prefetch the first scaled root, then stream the squares. #}
{{ exponent(full, 0) }}
{{ exponent(full, 1) }}
{{ clear() }}
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM.FIRST LR0 {{ full }} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
{% else %}
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BEQ LR8 CR0 {{ label }}_exp_tail ;;
{{ label }}_exp_loop:
{{ exponent(full, next_label=label ~ '_exp_loop') }}
{{ label }}_exp_tail:
{{ exponent(tail) }}

{# Square the roots and correct the reciprocal using the sum residual. #}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ; SET LR3 CR0 ; BEQ LR8 CR0 {{ label }}_sum_tail ;;
{{ label }}_sum_loop:
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 {{ label }}_sum_loop ;;
{{ label }}_sum_tail:
    MULT.RC.VS LR0 0 LR0 {{ tail }} {{ root }} ; AGG.SUM LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR0 ;;
{% endif %}
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    INC LR1 1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    MULT.EE LR13 CR1 0 LR0 {{ full }} {{ work }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR10 LR0 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ full }} {{ work }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ full }} {{ work }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ work }} {{ cr.tmp }} LR1 ;;

{% if paired %}
    SUB LR4 LR2 CR1 ;;
{% else %}
    SUB LR4 LR2 CR1 ; SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; BEQ LR8 CR0 {{ label }}_normalize_tail ;;
{{ label }}_normalize_loop:
{% endif %}
{% macro normalize(ds, streaming=false, next_label='') %}
{% set tile = 'LR3' %}
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST{% if not streaming %} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0{% endif %} ;;
    MULT.RC.VS LR0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD ;;
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ root }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} {{ tile }} ;;
    LD.MULT R0 {{ tile }} {{ cr.exps }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ work }} ; ACC.SUB ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} {{ tile }} ; LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR0 ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; LD.MULT R1 {{ tile }} {{ cr.exps }} ;;
    MULT.RC.VV LR10 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ;;
    MULT.RC.VV LR0 R1 0 LR0 {{ ds }} {{ work }} ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1{% if next_label %} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 {{ next_label }}{% endif %} ;;
{% endmacro %}
{% if paired %}
{% call(ds) tiles(label ~ '_normalize', true) %}
{{ normalize(ds) }}
{% endcall %}
{% else %}
{{ normalize(full, true, label ~ '_normalize_loop') }}
{{ label }}_normalize_tail:
{{ normalize(tail, true) }}
{% endif %}
    ADD LR2 LR2 {{ cr.K }} ;;
    BLT.S LR2 {{ cr.M }} {{ label }}_row ;;
    HALT ;;
{% endmacro %}
{{ process('generic', false) }}
{{ process('pair', true) }}
