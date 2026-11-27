{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro row(ds) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.EE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ; DEC LR1 1 ;;
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ cr.qf_in0 }}.L {{ cr.one }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.one }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ cr.qf_in0 }}.L {{ cr.one }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.one }} ;;
group:
    SET LR3 CR0 ; BEQ {{ cr.chunks }} CR1 partial ;;
chunk:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    {{ row(full) }}
    INC LR3 1 ; BLT.S LR3 {{ cr.last_chunk }} chunk ;;
partial:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    {{ row(tail) }}
    INC LR2 1 ; BLT.S LR2 {{ cr.last_group }} group ;;
    HALT ;;
