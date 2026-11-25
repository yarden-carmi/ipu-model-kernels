{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% macro clear() %}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% endmacro %}

{# Store the powers of two used to construct both coefficients exactly. #}
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
    SUB LR7 LR8 CR1 ;;
    SUB LR5 LR7 CR1 ;;
    BNE LR7 CR0 dispatch_single ;;
    BEQ {{ cr.tail }} {{ cr.full }} pair_row ;;
dispatch_single:
    BEQ LR8 CR0 single_start ;;
{% macro exp_store(ds, load='', first_load='', second_load='') %}
{# Two dyadic terms approximate log2(e)/2 with relative error below 5e-5. #}
{% for index in ['LR0','LR13'] %}
    MULT.RC.VV {{ index }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST {{ first_load }}{% endif %} ;;
    MULT.RC.VE {{ index }} LR13 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 {{ load }}{% else %} {{ second_load }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro normalize_store(ds, extra='') %}
    MULT.RC.VV LR0 R0 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ 'relu' if act_out0 | default('identity') == 'identity' else act_out0 }} {{ ds }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1 {{ extra }} ;;
{% endmacro %}
{% macro normalize(ds, label, next_label='') %}
    MULT.RC.VE LR0 LR13 0 LR0 {{ ds }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ ds }} {{ root }} {{ cr.exps }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.exps }}{% if not next_label %} ; ADD LR2 LR2 {{ cr.K }}{% endif %} ;;
{% if next_label == 'pair' %}
{{ normalize_store(ds, '; LD.MULT.CYCLIC LR1 ' ~ cr.roots ~ ' LR0') }}
{% elif next_label %}
{{ normalize_store(ds, '; LD.MULT.CYCLIC LR3 ' ~ cr.roots ~ ' LR0 ; INC LR3 1 ; BLT.S LR3 LR7 ' ~ next_label) }}
{% else %}
{{ normalize_store(ds, '; BLT.S LR2 ' ~ cr.M ~ ' ' ~ label ~ '_row') }}
{% endif %}
{% endmacro %}
{% macro process(label, paired) %}
{{ label }}_row:
{% if paired %}
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR4 LR2 CR1 ; SET LR3 CR0 ; SET LR1 CR1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; ACTIVATE.QUANTIZE identity {{ cr.single }}.H {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
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
{% if not paired %}
    SUB LR4 LR2 CR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
{% endif %}
{% if not paired %}
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
{% endif %}
{% if paired %}
{# Stream both roots without rescaling. Load the first after its coefficient's last use. #}
{{ exp_store(full, '; LD.MULT R0 LR4 ' ~ cr.in0, '; LD.MULT R1 LR1 ' ~ cr.tmp) }}
{{ exp_store(full, '', '; INC LR3 1', '; LD.MULT.CYCLIC LR0 ' ~ cr.roots ~ ' LR0') }}
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

{% if paired %}
{{ normalize(full, label, 'pair') }}
{{ normalize(full, label) }}
{% else %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; BEQ LR8 CR0 {{ label }}_normalize_tail ;;
{{ label }}_normalize_loop:
{{ normalize(full, label, label ~ '_normalize_loop') }}
{{ label }}_normalize_tail:
{{ normalize(tail, label) }}
{% endif %}
    HALT ;;
{% endmacro %}
{{ process('generic', false) }}
{{ process('pair', true) }}
single_start:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR1 CR1 ; SET LR3 CR0 ; DEC LR4 1 ;;
single_row:
{# Keep the input in R0 from max through exponentiation; no tile loops. #}
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ cr.single }}.H {{ q }} {{ cr.tmp }} LR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
{{ exp_store(tail, '', '; LD.MULT R1 LR1 ' ~ cr.tmp) }}
    LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ;;
    MULT.RC.VS LR0 0 LR0 {{ tail }} {{ root }} ; AGG.SUM.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE reciprocal {{ cr.single }}.H {{ root }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ tail }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ tail }} {{ root }} {{ cr.exps }} LR0 ; INC LR2 1 ;;
    LD.MULT R0 LR0 {{ cr.exps }} ; BEQ LR2 {{ cr.M }} single_last ;;
{{ normalize_store(tail, '; LD.MULT R0 LR2 ' ~ cr.in0 ~ ' ; B single_row') }}
single_last:
{{ normalize_store(tail) }}
    HALT ;;
