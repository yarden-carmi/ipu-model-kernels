{% set q = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set root = cr.scratch_qf ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set scalar = cr.scalar ~ '.H' %}
{% set act = act_out0 | default('identity') %}
{# Transpose one logical row at a time. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR2 1 ;;
transpose_group:
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR9 CR0 ;;
transpose_row:
    ADD LR5 LR12 LR4 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR8 LR15 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
transpose_gather:
    LD.MULT R0 LR5 CR0 ;;
    MULT.EE LR9 CR1 0 LR0 {{ full }} {{ q }} ; ACC.RESHAPE LRD6 LRD6 7 ; ADD LR5 LR5 LR10 ; DEC LR8 1 ;;
    ADDBI LRD6 1 ; BNE LR8 CR0 transpose_gather ;;
    ACTIVATE.QUANTIZE identity {{ tail }} {{ q }} {{ cr.trans }} LR2 ; INC LR2 1 ; INC LR3 1 ; INC LR9 1 ;;
    SET LR8 CR0 ;;
    INC LR8 128 ;;
    BLT.S LR9 LR8 transpose_no_wrap ;;
    SET LR9 CR0 ; INC LR4 1 ;;
transpose_no_wrap:
    BLT.S LR3 LR14 transpose_row ;;
    ADD LR12 LR12 LR11 ; INC LR1 1 ;;
    BLT.S LR1 LR13 transpose_group ;;
{# Construct exp2 coefficients used for exp(x/2). #}
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
    SET LR8 CR0 ;;
    INC LR8 8 ;;
    LD.MULT R0 LR0 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.ADD.FIRST ;;
{% for i in range(4) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ q }} ; ACC.SUB{% if loop.last %} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ q }} {{ cr.tmp }} LR8{% endif %} ;;
{% endfor %}
    SET LR13 CR0 ;;
    INC LR13 128 ;;
    LD.MULT.CYCLIC LR14 {{ cr.tmp }} LR13 ;;
    LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
    ADD LR10 LR13 LR13 ;;
    SET LR4 CR0 ; SET LR1 CR1 ;;
    DEC LR4 1 ;;
    BEQ {{ cr.qf_out0 }} {{ cr.e3 }} short_e3_start ;;
{% macro short_path(label, short_qf) %}
{{ label }}_start:
    LD.MULT R0 LR2 {{ cr.trans }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; AGG.MAX.FIRST LR0 {{ tail }} ; ACTIVATE.QUANTIZE identity {{ scalar }} {{ q }} {{ cr.tmp }} LR1 ;;
    LD.MULT R1 LR1 {{ cr.tmp }} ; MULT.RC.VV LR0 R0 0 LR0 {{ tail }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ tail }} {{ q }} ; ACC.SUB ;;
    MULT.RC.VV LR13 R0 0 LR0 {{ tail }} {{ q }} ; ACC.ADD ;;
    MULT.RC.VE LR13 LR13 0 LR0 {{ tail }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ tail }} {{ root }} {{ cr.roots }} LR0 ; LD.MULT R0 LR8 {{ cr.tmp }} ;;
{% for i in range(1,8) %}
    SET LR3 CR0 ;;
    INC LR3 {{ i }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ tail }} {{ q }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ tail }} {{ root }} {{ cr.roots }} LR3 ;;
{% endfor %}
{% for i in range(8) %}
    SET LR3 CR0 ;;
{% if i %}    INC LR3 {{ i }} ;;
{% endif %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ tail }} {{ root }} ; AGG.SUM{% if loop.first %}.FIRST{% endif %} LR0 {{ tail }}{% if loop.last %} ; ACTIVATE.QUANTIZE reciprocal {{ scalar }} {{ cr.scratch_qf }}.H {{ cr.tmp }} LR0{% endif %} ;;
{% endfor %}
{% for i in range(8) %}
    SET LR3 CR0 ;;
{% if i %}    INC LR3 {{ i }} ;;
{% endif %}
    LD.MULT.CYCLIC LR3 {{ cr.roots }} LR10 ;;
    MULT.RC.VS LR10 0 LR0 {{ tail }} {{ root }} ; ACC.ADD{% if loop.first %}.FIRST{% endif %}{% if loop.last %} ; ACTIVATE.QUANTIZE identity {{ tail }} {{ cr.scratch_qf }}.H {{ cr.exps }} LR0{% endif %} ;;
{% endfor %}
    LD.MULT R1 LR0 {{ cr.tmp }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.exps }} LR10 ;;
    MULT.RC.VE LR10 LR13 0 LR0 {{ tail }} {{ cr.scratch_qf }}.H ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act }} {{ tail }} {{ qo }} {{ cr.out0 }} LR4 ; INC LR4 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.rows }} {{ label }}_start ;;
    HALT ;;
{% endmacro %}
{{ short_path('short_e2', root) }}
{{ short_path('short_e3', root) }}
