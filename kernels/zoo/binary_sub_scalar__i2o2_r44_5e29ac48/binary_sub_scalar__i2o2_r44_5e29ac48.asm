{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro row(ds) %}
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; INC LR1 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR4 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.one }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.one }} ;;
group:
    SET LR3 CR1 ; BEQ {{ cr.chunks }} CR1 partial ;;
chunk:
    {{ row(full) }}
    INC LR3 1 ; BLT.S LR3 {{ cr.last_chunk }} chunk ;;
partial:
    {{ row(tail) }}
    INC LR2 1 ; BLT.S LR2 {{ cr.last_group }} group ;;
    HALT ;;
