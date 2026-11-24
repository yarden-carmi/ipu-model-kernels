{% macro product(coefficient, acc, ds) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ product(cr.fp_top, 'ADD.FIRST', ds) }}
    {{ product(cr.fp_base, 'SUB', ds) }}
    MULT.VE LR0 {{ cr.nx_scale }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    BEQ {{ cr.last }} {{ cr.full_lanes }} dense ;;
group:
    SET LR3 CR1 ;;
    BEQ LR3 {{ cr.chunks }} tail ;;
chunk:
    {{ row(cr.ds_pair ~ '.H') }}
    INC LR1 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.chunks }} chunk ;;
tail:
    {{ row(cr.ds_pair ~ '.L') }}
    INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.groups }} group ;;
    HALT ;;
dense:
    {{ row(cr.ds_pair ~ '.H') }}
    # The branch sees LR1 before the increment in this word.
    INC LR1 1 ; BLT.S LR1 {{ cr.last_row }} dense ;;
    HALT ;;
