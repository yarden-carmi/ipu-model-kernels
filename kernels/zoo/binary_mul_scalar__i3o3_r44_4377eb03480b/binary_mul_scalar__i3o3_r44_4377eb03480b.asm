{% macro product(coefficient, acc, ds) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ product(cr.fp_top, 'ADD.FIRST', ds) }}
    {{ product(cr.fp_base, 'SUB', ds) }}
    {{ product(cr.nx_scale, 'ADD', ds) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
group:
    SET LR3 CR1 ;;
chunk:
    BEQ LR3 {{ cr.chunks }} tail ;;
    {{ row(cr.ds_pair ~ '.H') }}
    INC LR1 1 ; INC LR3 1 ;;
    B chunk ;;
tail:
    {{ row(cr.ds_pair ~ '.L') }}
    INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.groups }} group ;;
    HALT ;;
