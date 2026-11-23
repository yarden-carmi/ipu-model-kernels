{# An accepted perturbation is at most 2^-12 relative, below half
   a quantization step for a value already represented in NX8. #}
{% macro copy_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR1 ;;
    BGE.S LR2 {{ cr.chunks }} tail ;;
chunk:
    {{ copy_row('CR15.L') }}
    INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.chunks }} chunk ;;
tail:
    {{ copy_row(cr.tail ~ '.L') }}
    HALT ;;
