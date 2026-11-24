{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR14 {{ coefficient }} 0 LR14 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds, prefetch=false) %}
    MULT.RC.VV LR14 R0 0 LR14 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
    ; INC LR3 1
    {% if prefetch %}; INC LR4 1 ; LD.MULT R0 LR4 {{ cr.in0 }}{% endif %}
{% endmacro %}

    SET LR14 CR0 ; SET LR4 CR0 ; SET LR3 CR0 ;;
    DEC LR3 1 ;;
    {# Synthesize the 1/8 coefficient row in the input format. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.scalar }} ;;
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT.CYCLIC LR14 {{ cr.scalar }} LR14 ; BNE LR15 CR0 partial ;;

    {# Stream each packed row once and stop prefetching before the buffer end. #}
    LD.MULT R0 LR4 {{ cr.in0 }} ; BEQ LR4 {{ cr.last_row }} final_row ;;
dense:
    {{ row(full, true) }} ; BLT.S LR4 {{ cr.penultimate_row }} dense ;;
final_row:
    {{ row(full) }} ; HALT ;;

partial:
    SET LR0 CR0 ;;
group:
    SET LR1 CR1 ; LD.MULT R0 LR4 {{ cr.in0 }} ; BEQ {{ cr.ic }} CR1 tail_row ;;
chunk:
    {{ row(full, true) }} ; INC LR1 1 ;;
    BLT.S LR1 {{ cr.ic }} chunk ;;
tail_row:
    {{ row(tail) }} ; INC LR0 1 ; INC LR4 1 ;;
    BLT.S LR0 {{ cr.groups }} group ;;
    HALT ;;
