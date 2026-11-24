{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR14 {{ coefficient }} 0 LR14 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro scatter(advance=false, prefetch=false) %}
    MULT.RC.VE LR14 LR11 0 LR14 {{ full }} {{ qi }} ; ACC.RESHAPE LRD12 LRD12 7
    {% if advance %}; ADDBI LRD12 1{% endif %}
    {% if prefetch %}; ADD LR4 LR4 {{ cr.ic }} ; LD.MULT R0 LR4 {{ cr.in0 }}{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}

    SET LR14 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    {# Form the 1/8 coefficient in the active input format. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.scalar }} ;;
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT.CYCLIC LR14 {{ cr.scalar }} LR14 ;;

batch:
    SET LR2 CR0 ; SET LR9 CR0 ; SET LR11 CR0 ;;
column:
    ADD LR10 LR1 LR9 ; SET LR5 CR0 ;;
head:
    SET LR4 LR10 ; SET LR7 CR0 ;;
tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR6 CR1 ;;
    SET LR8 CR0 ; INC LR7 1 ;;
    INC LR8 128 ; BNE LR7 {{ cr.oc }} gather ;;
    SET LR8 LR15 ;;
gather:
    LD.MULT R0 LR4 {{ cr.in0 }} ; BEQ LR8 CR1 singleton ;;
    {# Select one source column and scatter successive rows to output lanes. #}
    {{ scatter(prefetch=true) }} ; INC LR6 2 ;;
    BLT.S LR8 LR6 finish_gather ;;
gather_next:
    {{ scatter(advance=true, prefetch=true) }} ; INC LR6 1 ; BLT.S LR6 LR8 gather_next ;;
finish_gather:
    {{ scatter(advance=true) }} ; B gathered ;;
singleton:
    {{ scatter() }} ;;
gathered:
    ADD LR4 LR4 {{ cr.ic }} ; BEQ LR7 {{ cr.oc }} tail_store ;;
    {{ store(full) }}
    B tile ;;
tail_store:
    {{ store(tail) }}
    ADD LR10 LR10 {{ cr.plane_rows }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d1 }} head ;;
    INC LR2 1 ; INC.MODP2 LR11 CR1 7 ;;
    BGE.S LR2 {{ cr.out0_d3 }} batch_done ;;
    BNE LR11 CR0 column ;;
    INC LR9 1 ; B column ;;
batch_done:
    SUB LR1 LR10 LR9 ; DEC LR0 1 ;;
    BNE LR0 CR0 batch ;;
    HALT ;;
