{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds, control, prefetch=false) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
    {% if prefetch %}; INC LR2 1 ; LD.MULT R0 LR2 {{ cr.in0 }}{% endif %}
    ; {{ control }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    {# Materialize the coefficient in the input format for vector multiplies. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {% for i in range(8) %}
    {{ product('CR1', 'ADD.FIRST' if i == 0 else 'ADD') }}
    {% endfor %}
    ACTIVATE.QUANTIZE reciprocal {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; BEQ {{ full }} {{ tail }} dense ;;
    SET LR3 CR0 ; DEC LR1 1 ;;
group:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR4 CR1 ; BEQ {{ cr.ic }} CR1 partial ;;
chunk:
    {{ row(full, 'INC LR1 1 ; INC LR4 1 ; BLT.S LR4 ' ~ cr.last_chunk ~ ' chunk', true) }}
partial:
    {{ row(tail, 'INC LR1 1') }}
    INC LR2 1 ; INC LR3 1 ; BLT.S LR3 {{ cr.last_group }} group ;;
    HALT ;;
dense:
    DEC LR1 1 ; LD.MULT R0 LR2 {{ cr.in0 }} ; BEQ LR2 {{ cr.last_row }} final ;;
stream:
    {{ row(full, 'INC LR1 1 ; BLT.S LR2 ' ~ cr.penultimate ~ ' stream', true) }}
final:
    {{ row(full, 'INC LR1 1 ; HALT') }}
