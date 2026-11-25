{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set scalar = cr.single ~ '.H' %}
{% set act = act_out0 | default('identity') %}

{# Generate log2(e)/2 as 39/64 + 7/64, using two input-format terms. #}
{% macro power(delta,slot) %}
{% for i in range(delta) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} {{ slot }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro coefficient(base,unit,count) %}
    LD.MULT R0 {{ base }} {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT R0 {{ unit }} {{ cr.tmp }} ;;
{% for i in range(count) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} {{ unit }}{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR1 ; SET LR6 CR0 ;;
    INC LR6 5 ; SET LR9 CR0 ; SET LR2 CR0 ;;
    INC LR9 6 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR7 CR1 ; SET LR5 CR0 ;;
{{ power(1,'LR7') }}
{{ power(4,'LR6') }}
{{ power(4,'LR5') }}
{{ power(4,'LR9') }}
{{ coefficient('LR7','LR6',7) }}
{{ coefficient('LR5','LR9',5) }}
    SET LR13 CR0 ; SET LR11 CR0 ; SET LR4 CR0 ;;
    INC LR13 128 ; INC LR11 128 ;;
    INC LR11 128 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ; SET LR10 LR11 ;;
    LD.MULT.CYCLIC LR9 {{ cr.tmp }} LR13 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
    LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR12 ;;

{# Cache slot 256 holds the physical input row; LR10 selects a packed item. #}
{% macro input_load() %}
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR11 ;;
    INC LR3 1 ;;
{% endmacro %}
{% macro maximum(ds, first=false) %}
    MULT.RC.VE LR10 CR1 0 LR0 {{ ds }} {{ q }} ; AGG.MAX{% if first %}.FIRST{% endif %} LR0 {{ ds }} ;;
{% endmacro %}
row_start:
    SET LR3 LR2 ; ADD LR8 LR2 {{ cr.before_tail }} ;;
{{ input_load() }}
    BEQ LR2 LR8 short_max ;;
{{ maximum(full, true) }}
max_next:
    BEQ LR3 LR8 max_tail ;;
{{ input_load() }}
{{ maximum(full) }}
    B max_next ;;
max_tail:
{{ input_load() }}
{{ maximum(tail) }}
    B save_max ;;
short_max:
{{ maximum(tail, true) }}
save_max:
    ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR1 ; SET LR3 LR2 ; SET LR5 CR0 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;

{% macro exp_chunk(ds) %}
{{ input_load() }}
    LD.MULT R0 LR6 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; LD.MULT R0 LR9 {{ cr.tmp }} ;;
    MULT.RC.VV LR10 R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VE LR13 LR13 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ;;
    {# A common shift cancels in normalization and keeps exp2's input nonpositive. #}
    MULT.RC.VE LR12 CR1 0 LR0 {{ ds }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    BEQ LR3 LR8 exp_tail ;;
exp_full:
{{ exp_chunk(full) }}
    BLT.S LR3 LR8 exp_full ;;
exp_tail:
{{ exp_chunk(tail) }}

    ADD LR10 LR10 LR15 ; SET LR5 CR0 ;;
    BNE LR10 LR14 sum_start ;;
    SET LR10 LR11 ; SET LR2 LR3 ;;
sum_start:
{% macro sum_chunk(ds, first=false, extra='') %}
    LD.MULT.CYCLIC LR5 {{ cr.roots }} LR11 ;;
    MULT.RC.VS LR11 0 LR0 {{ ds }} {{ root }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }} {{ extra }} ; INC LR5 1 ;;
{% endmacro %}
{% set reciprocal = '; ACTIVATE.QUANTIZE reciprocal ' ~ scalar ~ ' ' ~ root ~ ' ' ~ cr.tmp ~ ' LR0' %}
    BEQ {{ cr.before_tail }} CR0 sum_short ;;
{{ sum_chunk(full, true) }}
    BEQ LR5 {{ cr.before_tail }} sum_tail ;;
sum_loop:
{{ sum_chunk(full) }}
    BLT.S LR5 {{ cr.before_tail }} sum_loop ;;
sum_tail:
{{ sum_chunk(tail, false, reciprocal) }}
    B normalize_start ;;
sum_short:
{{ sum_chunk(tail, true, reciprocal) }}

normalize_start:
    LD.MULT R1 LR0 {{ cr.tmp }} ; SET LR5 CR0 ;;
{% macro normalize(ds) %}
    LD.MULT.CYCLIC LR5 {{ cr.roots }} LR11 ;;
    MULT.RC.VE LR11 LR13 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.tmp }} LR1 ; INC LR5 1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
    BEQ {{ cr.before_tail }} CR0 normalize_tail ;;
normalize_loop:
{{ normalize(full) }}
    BLT.S LR5 {{ cr.before_tail }} normalize_loop ;;
normalize_tail:
{{ normalize(tail) }}
    BLT.S LR4 {{ cr.M }} row_start ;;
    HALT ;;
