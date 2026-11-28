{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set scalar = cr.single ~ '.H' %}
{% set act = act_out0 | default('identity') %}
{% set wide_act = 'relu' if act == 'identity' else act %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
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
    SET LR0 CR0 ; SET LR6 CR0 ; SET LR14 CR0 ;;
    INC LR6 5 ; INC LR14 6 ; SET LR2 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ; SET LR7 CR1 ; SET LR5 CR0 ;;
{{ power(1,'LR7') }}
{{ power(4,'LR6') }}
{{ power(4,'LR5') }}
{{ power(4,'LR14') }}
{{ coefficient('LR7','LR6',7) }}
{{ coefficient('LR5','LR14',5) }}
    SET LR13 CR0 ; SET LR4 CR0 ; SET LR8 {{ cr.K }} ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR13 ; INC LR13 128 ; DEC LR8 1 ;;
    SUB LR7 LR8 CR1 ; SET LR10 LR13 ; SET LR11 LR13 ;;
    SUB LR5 LR7 CR1 ; INC LR10 128 ; INC LR11 128 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ; INC LR11 128 ; BNE LR7 CR0 dispatch_single ;;
    BEQ {{ cr.tail }} {{ cr.full }} pair_row ;;
dispatch_single:
    BEQ LR8 CR0 single_start ;;
{% macro exp_store(ds, load='', first_load='', second_load='') %}
{% for index in ['LR0','LR13'] %}
    MULT.RC.VV {{ index }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST {{ first_load }}{% endif %} ;;
    MULT.RC.VE {{ index }} LR13 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 {{ load }}{% else %} {{ second_load }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds, slot, extra='') %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ wide_act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1 {{ extra }} ;;
{% endmacro %}
{% macro sum_recip(ds, slot, extra='') %}
    MULT.RC.VS {{ slot }} 0 LR0 {{ ds }} {{ root }} ; AGG.SUM LR0 {{ ds }} ; ACTIVATE.QUANTIZE reciprocal {{ scalar }} {{ root }} {{ cr.tmp }} LR0 {{ extra }} ;;
{% endmacro %}
generic_row:
    SET LR4 LR2 ;;
{{ clear() }}
    ADD LR9 LR2 LR8 ; DEC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; DEC LR9 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BEQ LR4 LR9 generic_max_tail ;;
generic_max_next:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BLT.S LR4 LR9 generic_max_next ;;
generic_max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX LR0 {{ tail }} ;;
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.VE LR13 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    SUB LR4 LR2 CR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; SUB LR3 LR0 CR1 ;;
    SET LR12 CR0 ;;
    INC LR12 4 ;;
    BEQ {{ cr.K }} LR12 generic_exp_four ;;
generic_exp_loop:
{{ exp_store(full, '; LD.MULT R0 LR4 ' ~ cr.in0 ~ ' ; INC LR4 1 ; INC LR3 1 ; BLT.S LR3 LR5 generic_exp_loop') }}
    B generic_exp_tail ;;
generic_exp_four:
{% for i in range(3) %}
{{ exp_store(full, '; LD.MULT R0 LR4 ' ~ cr.in0 ~ ' ; INC LR4 1 ; INC LR3 1') }}
{% endfor %}
generic_exp_tail:
{{ exp_store(tail, '; INC LR3 1') }}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ; SET LR3 CR0 ;;
generic_sum_loop:
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 generic_sum_loop ;;
{{ sum_recip(tail, 'LR0') }}
    LD.MULT R1 LR0 {{ cr.tmp }} ; SUB LR4 LR2 CR1 ; SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ;;
{% macro scale(ds, root_slot, exp_slot, extra='', work=root) %}
    MULT.RC.VE {{ root_slot }} LR13 0 LR0 {{ ds }} {{ work }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ work }} {{ cr.exps }} {{ exp_slot }} {{ extra }} ;;
{% endmacro %}
{% macro normalize(ds, next_label='') %}
{{ scale(ds, 'LR0', 'LR0') }}
    LD.MULT R0 LR0 {{ cr.exps }}{% if not next_label %} ; ADD LR2 LR2 {{ cr.K }}{% endif %} ;;
{{ store(ds, 'LR0', '; LD.MULT.CYCLIC LR3 ' ~ cr.roots ~ ' LR0 ; INC LR3 1 ; BLT.S LR3 LR7 ' ~ next_label if next_label else '; BLT.S LR2 ' ~ cr.M ~ ' generic_row') }}
{% endmacro %}
generic_normalize_loop:
{{ normalize(full, 'generic_normalize_loop') }}
{{ normalize(tail) }}
    HALT ;;
pair_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR12 LR2 CR1 ; SET LR3 CR0 ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R0 LR1 {{ cr.tmp }} ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.VE LR13 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ full }} {{ q }} {{ cr.tmp }} LR1 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ exp_store(full, '; LD.MULT R0 LR12 ' ~ cr.in0, '; LD.MULT R1 LR1 ' ~ cr.tmp) }}
{{ exp_store(full, '', '; INC LR3 1', '; LD.MULT.CYCLIC LR0 ' ~ cr.roots ~ ' LR10') }}
    MULT.RC.VS LR10 0 LR0 {{ full }} {{ root }} ; AGG.SUM.FIRST LR0 {{ full }} ; LD.MULT.CYCLIC LR1 {{ cr.roots }} LR11 ;;
{{ sum_recip(full, 'LR11', '; SUB LR4 LR2 CR1 ; ADD LR2 LR2 ' ~ cr.K) }}
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
{{ scale(full, 'LR10', 'LR0') }}
{{ scale(full, 'LR11', 'LR1', '; LD.MULT R0 LR0 ' ~ cr.exps) }}
{{ store(full, 'LR10', '; LD.MULT R0 LR1 ' ~ cr.exps) }}
{{ store(full, 'LR11', '; BLT.S LR2 ' ~ cr.M ~ ' pair_row') }}
    HALT ;;
single_start:
    SET LR1 CR1 ; SET LR9 {{ cr.M }} ; DEC LR4 1 ;;
    DEC LR9 1 ; BEQ {{ cr.qf_out0 }} {{ cr.e3 }} short_e3_start ;;
{% macro short_path(label, short_qf) %}
{% macro short_max(extra='') %}
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR1 {{ extra }} ;;
{% endmacro %}
{% macro short_exp(dest, extra='') %}
    LD.MULT R1 LR1 {{ cr.tmp }} ; MULT.RC.VV LR0 R0 0 LR0 {{ tail }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ tail }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ tail }} {{ q }} ; ACC.ADD {{ extra }} ;;
    MULT.RC.VE LR13 LR13 0 LR0 {{ tail }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ tail }} {{ short_qf }} {{ cr.roots }} {{ dest }} ;;
{% endmacro %}
{% macro short_sum(slot, dest, extra='') %}
    MULT.RC.VS {{ slot }} 0 LR0 {{ tail }} {{ short_qf }} ; AGG.SUM.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE rsqrt {{ scalar }} {{ short_qf }} {{ cr.tmp }} {{ dest }} {{ extra }} ;;
{% endmacro %}
{% macro short_store(slot, extra='') %}
    MULT.RC.VS {{ slot }} 0 LR0 {{ tail }} {{ short_qf }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1 {{ extra }} ;;
{% endmacro %}
{{ label }}_start:
    LD.MULT R0 LR2 {{ cr.in0 }} ; BEQ LR9 CR0 {{ label }}_loaded_tail ;;
{{ short_max('; INC LR2 1') }}
{{ short_exp('LR0', '; LD.MULT R0 LR2 ' ~ cr.in0) }}
{{ short_max('; INC LR2 1 ; LD.MULT.CYCLIC LR0 ' ~ cr.roots ~ ' LR10') }}
{{ short_exp('LR1') }}
{{ short_sum('LR10', 'LR0', '; LD.MULT.CYCLIC LR1 ' ~ cr.roots ~ ' LR11') }}
{{ short_sum('LR11', 'LR1', '; LD.MULT R1 LR0 ' ~ cr.tmp) }}
{{ scale(tail, 'LR10', 'LR0', '; LD.MULT R1 LR1 ' ~ cr.tmp, short_qf) }}
{{ scale(tail, 'LR11', 'LR1', '; LD.MULT.CYCLIC LR0 ' ~ cr.exps ~ ' LR10', short_qf) }}
{{ short_store('LR10', '; LD.MULT.CYCLIC LR1 ' ~ cr.exps ~ ' LR11') }}
{{ short_store('LR11', '; BLT.S LR2 LR9 ' ~ label ~ '_start') }}
    BEQ LR2 {{ cr.M }} {{ label }}_done ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ label }}_loaded_tail:
{{ short_max() }}
{{ short_exp('LR0') }}
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR10 ;;
{{ short_sum('LR10','LR0') }}
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
{{ scale(tail, 'LR10', 'LR0', work=short_qf) }}
    LD.MULT.CYCLIC LR0 {{ cr.exps }} LR10 ;;
{{ short_store('LR10') }}
{{ label }}_done:
    HALT ;;
{% endmacro %}
{{ short_path('short_e2', root) }}
{{ short_path('short_e3', cr.scratch_qf ~ '.H') }}
