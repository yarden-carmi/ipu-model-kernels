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
{% for p,c,s in [(5,23,5),(13,21,6)] %}
{{ coefficient(p,c,s) }}
{% if s != 5 %}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR12 ;;
{% endif %}
{% endfor %}
{{ coefficient(16,1,10) }}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR11 ;;
    SET LR8 {{ cr.K }} ;;
    DEC LR8 1 ;;
    SUB LR7 LR8 CR1 ;;
    SUB LR5 LR7 CR1 ;;
    SET LR2 CR0 ;;
{{ imm('LR13',128) }}
{{ imm('LR14',7) }}
{{ imm('LR6',5) }}
    BEQ LR11 {{ cr.n }} pair_row ;;
    BEQ LR8 CR0 single_row ;;
{% macro process(label, paired, single=false) %}
{{ label }}_row:
{% if single %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR1 CR1 ; SET LR3 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
{% elif paired %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR4 LR2 CR1 ; SET LR3 CR0 ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
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
{% if not paired and not single %}
    SUB LR4 LR2 CR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
{% endif %}
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% macro exp_store(ds, load='') %}
{# Two dyadic terms approximate log2(e)/2 with relative error below 5e-5. #}
{% for index in ['LR0','LR12'] %}
    MULT.RC.VV {{ index }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ index }} LR13 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 {{ load }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro exponent(ds, pair_tile=-1) %}
{{ exp_store(ds) }}
    LD.MULT R0 LR3 {{ cr.roots }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.roots }} LR3{% if pair_tile == 1 %} ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0{% endif %} ;;
{% if pair_tile == 0 %}
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR3 1 ;;
{% endif %}
{% endmacro %}
{% if single %}
{# R0 still holds the input from the max reduction. #}
{{ exp_store(tail) }}
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ tail }} {{ root }} ; AGG.SUM.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE reciprocal {{ cr.single }}.H {{ root }} {{ cr.tmp }} LR0 ;;
{% elif paired %}
{# Prefetch the first scaled root, then stream the squares. #}
{{ exponent(full, 0) }}
{{ exponent(full, 1) }}
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM.FIRST LR0 {{ full }} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; ACTIVATE.QUANTIZE reciprocal {{ cr.single }}.H {{ root }} {{ cr.tmp }} LR0 ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ;;
{% else %}
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; SUB LR3 LR0 CR1 ; BEQ LR8 CR0 {{ label }}_exp_tail ;;
{{ label }}_exp_loop:
{{ exp_store(full, '; LD.MULT R0 LR4 ' ~ cr.in0 ~ ' ; INC LR4 1 ; INC LR3 1 ; BLT.S LR3 LR5 ' ~ label ~ '_exp_loop') }}
{{ label }}_exp_tail:
{{ exp_store(tail, '; INC LR3 1') }}
{{ label }}_exp_ready:

{# Square the roots and take the reciprocal of their row sum. #}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ; SET LR3 CR0 ; BEQ LR8 CR0 {{ label }}_sum_tail ;;
{{ label }}_sum_loop:
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 {{ label }}_sum_loop ;;
{{ label }}_sum_tail:
    MULT.RC.VS LR0 0 LR0 {{ tail }} {{ root }} ; AGG.SUM LR0 {{ tail }} ; ACTIVATE.QUANTIZE reciprocal {{ cr.single }}.H {{ root }} {{ cr.tmp }} LR0 ;;
{% endif %}
    LD.MULT R1 LR0 {{ cr.tmp }} ; SUB LR4 LR2 CR1 ; SET LR3 CR0 ;;

{% if not paired and not single %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; BEQ LR8 CR0 {{ label }}_normalize_tail ;;
{{ label }}_normalize_loop:
{% endif %}
{% macro normalize(ds, next_label='') %}
    MULT.RC.VE LR0 LR13 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.exps }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.exps }}{% if not next_label %} ; ADD LR2 LR2 {{ cr.K }}{% endif %} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ 'relu' if act_out0 | default('identity') == 'identity' else act_out0 }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1{% if next_label == 'pair' %} ; LD.MULT.CYCLIC LR1 {{ cr.roots }} LR0{% elif next_label %} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 {{ next_label }}{% else %} ; BLT.S LR2 {{ cr.M }} {{ label }}_row{% endif %} ;;
{% endmacro %}
{% if paired %}
{{ normalize(full, 'pair') }}
{{ normalize(full) }}
{% elif single %}
{{ normalize(tail) }}
{% else %}
{{ normalize(full, label ~ '_normalize_loop') }}
{{ label }}_normalize_tail:
{{ normalize(tail) }}
{% endif %}
    HALT ;;
{% endmacro %}
{{ process('generic', false) }}
{{ process('pair', true) }}
{{ process('single', false, true) }}
