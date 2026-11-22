{% macro term(coefficient, acc, ds) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro compute(ds) %}
    {{ term(cr.fp_hi, 'ADD.FIRST', ds) }}
    {{ term(cr.fp_hi_base, 'SUB', ds) }}
    {{ term(cr.fp_lo, 'ADD', ds) }}
    {{ term(cr.fp_lo_base, 'SUB', ds) }}
    {{ term(cr.nx_hi, 'ADD', ds) }}
    {{ term(cr.nx_lo, 'ADD', ds) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
group:
    SET LR3 CR1 ;;
chunk:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BEQ LR3 {{ cr.chunks }} tail ;;
    {{ compute(cr.ds_pair ~ '.H') }}
    INC LR1 1 ; INC LR3 1 ;;
    B chunk ;;
tail:
    {{ compute(cr.ds_pair ~ '.L') }}
    INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.groups }} group ;;
    HALT ;;
