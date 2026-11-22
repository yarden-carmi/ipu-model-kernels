{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR14 {{ coefficient }} 0 LR14 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro scatter() %}
    MULT.RC.VE LR14 LR11 0 LR14 {{ full }} {{ qi }} ; ACC.RESHAPE LRD12 LRD12 7
{% endmacro %}
    SET LR14 CR0 ; SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR3 CR0 ;;
{# Build ones, then synthesize the scale in both arithmetic modes. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.scalar }} ;;
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT.CYCLIC LR14 {{ cr.scalar }} LR14 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
plane:
    SET LR2 CR0 ; SET LR10 LR1 ; SET LR11 CR0 ;;
column:
    SET LR4 LR10 ; SET LR7 CR0 ;;
tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR6 CR1 ;;
    SET LR8 LR9 ; INC LR7 1 ;;
    BNE LR7 {{ cr.oc }} gather ;;
    SET LR8 LR15 ;;
gather:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {{ scatter() }} ;;
    {# Control sees the old LR6, which already counts the row just scattered. #}
    ADDBI LRD12 1 ; ADD LR4 LR4 {{ cr.ic }} ; INC LR6 1 ; BLT.S LR6 LR8 gather ;;
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
    BEQ LR7 {{ cr.oc }} tail_store ;;
    {{ store(full) }}
    B tile ;;
tail_store:
    {{ store(tail) }}
    INC LR2 1 ; INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 same_chunk ;;
    INC LR10 1 ;;
same_chunk:
    BLT.S LR2 {{ cr.w }} column ;;
    ADD LR1 LR1 {{ cr.plane_rows }} ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.planes }} plane ;;
    HALT ;;
