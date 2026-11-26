{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}
{% macro power(delta,slot) %}
{% for i in range(delta) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} {{ slot }}{% endif %}{% if slot == 'LR6' and loop.index <= 3 %} ; INC LR12 {% if loop.index <= 2 %}128{% else %}106{% endif %}{% endif %}{% if slot == 'LR7' %} ; ADD LR15 LR15 {{ cr.qf_out0 }}.L{% endif %} ;;
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
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR0 ; SET LR15 {{ cr.n }} ; SET LR12 CR0 ;;
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
{% set act = 'relu' if act_out0 | default('identity') == 'identity' else act_out0 %}
{% macro store(ds, slot, extra='') %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1 {{ extra }} ;;
{% endmacro %}
{% macro sum_recip(ds, slot, first, extra='', offset='LR0') %}
    MULT.RC.VS {{ slot }} 0 LR0 {{ ds }} {{ root }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR0 {{ ds }} ; ACTIVATE.QUANTIZE reciprocal {{ cr.single }}.H {{ root }} {{ cr.tmp }} {{ offset }} {{ extra }} ;;
{% endmacro %}
generic_row:
{% set label = 'generic' %}
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
    SUB LR4 LR2 CR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; SUB LR3 LR0 CR1 ; BEQ LR8 CR0 {{ label }}_exp_tail ;;
{{ label }}_exp_loop:
{{ exp_store(full, '; LD.MULT R0 LR4 ' ~ cr.in0 ~ ' ; INC LR4 1 ; INC LR3 1 ; BLT.S LR3 LR5 ' ~ label ~ '_exp_loop') }}
{{ label }}_exp_tail:
{{ exp_store(tail, '; INC LR3 1') }}
{{ label }}_exp_ready:
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ; SET LR3 CR0 ; BEQ LR8 CR0 {{ label }}_sum_tail ;;
{{ label }}_sum_loop:
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 {{ label }}_sum_loop ;;
{{ label }}_sum_tail:
{{ sum_recip(tail, 'LR0', false) }}
    LD.MULT R1 LR0 {{ cr.tmp }} ; SUB LR4 LR2 CR1 ; SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; BEQ LR8 CR0 {{ label }}_normalize_tail ;;
{{ label }}_normalize_loop:
{% macro normalize(ds, next_label='') %}
    MULT.RC.VE LR0 LR13 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.exps }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.exps }}{% if not next_label %} ; ADD LR2 LR2 {{ cr.K }}{% endif %} ;;
{{ store(ds, 'LR0', '; LD.MULT.CYCLIC LR3 ' ~ cr.roots ~ ' LR0 ; INC LR3 1 ; BLT.S LR3 LR7 ' ~ next_label if next_label else '; BLT.S LR2 ' ~ cr.M ~ ' generic_row') }}
{% endmacro %}
{{ normalize(full, label ~ '_normalize_loop') }}
{{ label }}_normalize_tail:
{{ normalize(tail) }}
    HALT ;;
pair_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR12 LR2 CR1 ; SET LR3 CR0 ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; ACTIVATE.QUANTIZE identity {{ cr.single }}.H {{ q }} {{ cr.tmp }} LR1 ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
{{ exp_store(full, '; LD.MULT R0 LR12 ' ~ cr.in0, '; LD.MULT R1 LR1 ' ~ cr.tmp) }}
{{ exp_store(full, '', '; INC LR3 1', '; LD.MULT.CYCLIC LR0 ' ~ cr.roots ~ ' LR10') }}
    MULT.RC.VS LR10 0 LR0 {{ full }} {{ root }} ; AGG.SUM.FIRST LR0 {{ full }} ; LD.MULT.CYCLIC LR1 {{ cr.roots }} LR11 ;;
{{ sum_recip(full, 'LR11', false, '; SUB LR4 LR2 CR1 ; ADD LR2 LR2 ' ~ cr.K) }}
{% macro scale(ds, root_slot, exp_slot, extra='') %}
    MULT.RC.VE {{ root_slot }} LR13 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.exps }} {{ exp_slot }} {{ extra }} ;;
{% endmacro %}
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
{{ scale(full, 'LR10', 'LR0') }}
{{ scale(full, 'LR11', 'LR1', '; LD.MULT R0 LR0 ' ~ cr.exps) }}
{{ store(full, 'LR10', '; LD.MULT R0 LR1 ' ~ cr.exps) }}
{{ store(full, 'LR11', '; BLT.S LR2 ' ~ cr.M ~ ' pair_row') }}
    HALT ;;
single_start:
    SET LR9 {{ cr.M }} ; SET LR1 CR1 ; BEQ LR15 LR12 accurate_row ;;
single_resume:
    DEC LR9 1 ; DEC LR4 1 ; BEQ LR9 CR1 single_last ;;
{% macro single_max(extra='') %}
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ cr.single }}.H {{ q }} {{ cr.tmp }} LR1 {{ extra }} ;;
{% endmacro %}
{% macro single_exp(extra='', prefetch='') %}
{{ single_max() }}
{{ exp_store(tail, extra, '; LD.MULT R1 LR1 ' ~ cr.tmp ~ ' ; INC LR2 1', prefetch) }}
{% endmacro %}
single_row:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR3 CR0 ;;
{{ single_exp('; LD.MULT R0 LR2 ' ~ cr.in0) }}
{{ single_max('; SET LR3 CR1') }}
{{ exp_store(tail, '', '; LD.MULT R1 LR1 ' ~ cr.tmp ~ ' ; INC LR2 1', '; LD.MULT.CYCLIC LR0 ' ~ cr.roots ~ ' LR10') }}
{{ sum_recip(tail, 'LR10', true, '; LD.MULT.CYCLIC LR1 ' ~ cr.roots ~ ' LR11') }}
{{ sum_recip(tail, 'LR11', true, '; LD.MULT R1 LR0 ' ~ cr.tmp, 'LR1') }}
{{ scale(tail, 'LR10', 'LR0', '; LD.MULT R1 LR1 ' ~ cr.tmp) }}
{{ scale(tail, 'LR11', 'LR1', '; LD.MULT R0 LR0 ' ~ cr.exps) }}
{{ store(tail, 'LR10', '; LD.MULT R0 LR1 ' ~ cr.exps) }}
{{ store(tail, 'LR11', '; BLT.S LR2 LR9 single_row') }}
    BEQ LR2 {{ cr.M }} single_done ;;
single_last:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR3 CR0 ;;
{{ single_exp() }}
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR10 ;;
{{ sum_recip(tail, 'LR10', true) }}
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
{{ scale(tail, 'LR10', 'LR0') }}
    LD.MULT R0 LR0 {{ cr.exps }} ;;
{{ store(tail, 'LR10') }}
single_done:
    HALT ;;
accurate_row:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ cr.single }}.H {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% for coeff in ['LR0', 'LR13'] %}
    MULT.RC.VV {{ coeff }} R0 0 LR0 {{ tail }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ coeff }} LR13 0 LR0 {{ tail }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ tail }} {{ root }} {{ cr.tmp }} LR1{% endif %} ;;
{% endfor %}
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ tail }} {{ root }} ; AGG.SUM.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE rsqrt {{ cr.single }}.H {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ tail }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ tail }} {{ root }} {{ cr.tmp }} LR1 ;;
    LD.MULT.CYCLIC LR1 {{ cr.tmp }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ tail }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
    BNE LR4 {{ cr.M }} accurate_row ;;
    HALT ;;
