{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    BEQ CR1 {{ cr.chunks }} single ;;
group:
    SET LR3 CR1 ;;
chunk:
    {{ row(cr.ds_pair ~ '.H') }}
    INC LR1 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.chunks }} chunk ;;
    {{ row(cr.ds_pair ~ '.L') }}
    INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.groups }} group ;;
    HALT ;;
single:
    {{ row(cr.ds_pair ~ '.L') }}
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.groups }} single ;;
    HALT ;;
