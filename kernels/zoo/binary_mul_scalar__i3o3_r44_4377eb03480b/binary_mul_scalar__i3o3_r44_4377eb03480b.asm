{% macro product(coefficient, acc, ds) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.{{ acc }}
{% endmacro %}
{% macro load_row() %}
    LD.MULT R0 LR1 {{ cr.in0 }}
{% endmacro %}
{% macro row(ds, prefetch=false) %}
    {{ product(cr.fp_top, 'ADD.FIRST', ds) }} ;;
    {{ product(cr.fp_base, 'SUB', ds) }} ;;
    {{ product(cr.nx_scale, 'ADD', ds) }}
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
    ; INC LR4 1 ; INC LR1 1
    {% if prefetch %}; {{ load_row() }} ; BLT.S LR1 {{ cr.penultimate_row }} dense{% endif %} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    {# The store sees the post-increment LR4, the branch the pre-increment LR1. #}
    DEC LR4 1 ;;
    BEQ {{ cr.last }} {{ cr.full_lanes }} dense_start ;;
group:
    SET LR3 CR1 ;;
    BEQ LR3 {{ cr.chunks }} tail ;;
chunk:
    {{ load_row() }} ;;
    {{ row(cr.ds_pair ~ '.H') }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.chunks }} chunk ;;
tail:
    {{ load_row() }} ;;
    {{ row(cr.ds_pair ~ '.L') }}
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.groups }} group ;;
    HALT ;;
dense_start:
    {{ load_row() }} ; BEQ LR1 {{ cr.last_row }} dense_final ;;
dense:
    {# MULT uses the current row; the load uses the incremented pointer. #}
    {{ row(cr.ds_pair ~ '.H', true) }}
dense_final:
    {{ row(cr.ds_pair ~ '.H') }}
    HALT ;;
