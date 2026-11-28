{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro compute(ds) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
    ; INC LR1 1 ; INC LR2 1
{% endmacro %}
{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ compute(ds) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR2 1 ; SET LR3 {{ cr.groups }} ;;
    {# Materialize 1/sqrt(32) in the input format before multiplying rows. #}
    {{ coefficient('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ coefficient(cr.fp_hi, 'ADD.FIRST') }}
    {{ coefficient(cr.fp_lo, 'SUB') }}
    {{ coefficient(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; SET LR4 {{ cr.rows }} ; BNE {{ cr.remainder }} CR0 group ;;

    {# The load sees the incremented offset, while multiply sees the previous R0. #}
    LD.MULT R0 LR1 {{ cr.in0 }} ; DEC LR4 1 ; BEQ LR4 CR1 final_row ;;
stream:
    {{ compute(full) }} ; LD.MULT R0 LR1 {{ cr.in0 }} ; DEC LR4 1 ; BNE LR4 CR1 stream ;;
final_row:
    {{ compute(full) }} ; HALT ;;

group:
    SET LR4 {{ cr.full_chunks }} ; BEQ {{ cr.full_chunks }} CR0 last_chunk ;;
chunk:
    {{ row(full) }} ; DEC LR4 1 ; BNE LR4 CR1 chunk ;;
last_chunk:
    {{ row(tail) }} ; DEC LR3 1 ; BNE LR3 CR1 group ;;
    HALT ;;
