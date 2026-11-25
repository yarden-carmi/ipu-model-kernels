{% set full = cr.ds_pair ~ '.H' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro scalar_product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro store_row(start) %}
    MULT.RC.VV {{ start }} R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR2 CR0 ; SET LR3 {{ cr.in0_d3 }} ;;
    {# Build a broadcast vector of 1/8 in the input format. #}
    {{ scalar_product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ scalar_product(cr.fp_hi, 'ADD.FIRST') }}
    {{ scalar_product(cr.fp_lo, 'SUB') }}
    {{ scalar_product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;

row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    {{ store_row('LR0') }}
    INC LR2 1 ;;
    {{ store_row('LR3') }}
    INC LR2 1 ;;
    INC LR1 1 ; BLT.S LR1 {{ cr.last }} row ;;
    HALT ;;
