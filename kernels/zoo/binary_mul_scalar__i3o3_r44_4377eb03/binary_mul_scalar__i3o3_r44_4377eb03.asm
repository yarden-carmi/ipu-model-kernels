{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc, ds) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ ds }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds, prefetch=false) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
    ; INC LR2 1
    {% if prefetch %}; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR2 1 ;;
    {# Seed a row of ones, then construct the scale in the input format. #}
    {{ product('CR0', 'ADD.FIRST', full) }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ product(cr.fp_top, 'ADD.FIRST', full) }}
    {{ product(cr.fp_base, 'SUB', full) }}
    {{ product(cr.nx_scale, 'ADD', full) }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; BNE LR5 CR0 partial ;;

    LD.MULT R0 LR1 {{ cr.in0 }} ; BGE.S LR1 {{ cr.last_row }} final_row ;;
dense:
    {{ row(full, true) }} ; BLT.S LR1 {{ cr.penultimate_row }} dense ;;
final_row:
    {{ row(full) }} ; HALT ;;

partial:
    SET LR4 CR0 ;;
group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.chunks }} CR1 tail_row ;;
chunk:
    {{ row(full, true) }} ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.chunks }} chunk ;;
tail_row:
    {{ row(tail) }} ; INC LR4 1 ; INC LR1 1 ;;
    BLT.S LR4 {{ cr.groups }} group ;;
    HALT ;;
