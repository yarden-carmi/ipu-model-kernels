{% set q = cr.qf_in0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set act = 'relu' if act_out0 | default('identity') == 'identity' else act_out0 %}
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
{% macro exp_store(ds, extra='') %}
{% for index in ['LR0','LR13'] %}
    MULT.RC.VV {{ index }} R0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %} ;;
    MULT.RC.VE {{ index }} LR13 0 LR0 {{ ds }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ root }} {{ cr.roots }} LR3 {{ extra }}{% endif %} ;;
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
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ; INC LR11 128 ;;
row:
    SET LR4 LR2 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
    ADD LR9 LR2 LR8 ; DEC LR4 1 ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; DEC LR9 1 ; BEQ LR8 CR0 max_single ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX.FIRST LR0 {{ full }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BEQ LR4 LR9 max_tail ;;
max_loop:
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; AGG.MAX LR0 {{ full }} ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BLT.S LR4 LR9 max_loop ;;
max_tail:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX LR0 {{ tail }} ;;
    B max_ready ;;
max_single:
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ;;
max_ready:
    SET LR1 CR1 ;;
    ACTIVATE.QUANTIZE relu {{ full }} {{ q }} {{ cr.tmp }} LR1 ;;
    SUB LR4 LR2 CR1 ; LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ;;
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; SUB LR3 LR0 CR1 ; BEQ LR8 CR0 exp_tail ;;
exp_loop:
{{ exp_store(full, '; LD.MULT R0 LR4 ' ~ cr.in0 ~ ' ; INC LR4 1 ; INC LR3 1 ; BLT.S LR3 LR5 exp_loop') }}
exp_tail:
{{ exp_store(tail, '; INC LR3 1') }}
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR0 {{ cr.roots }} LR0 ; SET LR3 CR0 ; BEQ LR8 CR0 sum_tail ;;
sum_loop:
    MULT.RC.VS LR0 0 LR0 {{ full }} {{ root }} ; AGG.SUM LR0 {{ full }} ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 sum_loop ;;
sum_tail:
    MULT.RC.VS LR0 0 LR0 {{ tail }} {{ root }} ; AGG.SUM LR0 {{ tail }} ; ACTIVATE.QUANTIZE reciprocal {{ cr.single }}.H {{ root }} {{ cr.tmp }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.tmp }} ; SUB LR4 LR2 CR1 ; SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; BEQ LR8 CR0 normalize_tail ;;
normalize_loop:
    MULT.RC.VE LR0 LR13 0 LR0 {{ full }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ full }} {{ root }} {{ cr.exps }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.exps }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR4 1 ; LD.MULT.CYCLIC LR3 {{ cr.roots }} LR0 ; INC LR3 1 ; BLT.S LR3 LR7 normalize_loop ;;
normalize_tail:
    MULT.RC.VE LR0 LR13 0 LR0 {{ tail }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ tail }} {{ root }} {{ cr.exps }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.exps }} ; ADD LR2 LR2 {{ cr.K }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ tail }} {{ root }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR4 1 ; BLT.S LR2 {{ cr.M }} row ;;
    HALT ;;
