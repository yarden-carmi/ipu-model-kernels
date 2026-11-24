{% macro lhs() %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.active_in0 }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR5 1 ; LD.MULT R0 LR5 {{ cr.in1 }}
{% endmacro %}
{% macro rhs() %}
    MULT.VE LR0 CR1 0 LR0 {{ cr.active_in1 }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active_out0 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ;;
    SUB LR5 LR0 CR1 ; LD.MULT R0 LR0 {{ cr.in0 }} ; BEQ CR0 {{ cr.last }} tail ;;
row:
    {{ lhs() }} ;;
    {{ rhs() }} ; LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 1 ; BLT.S LR6 {{ cr.prefetch_limit }} row ;;
tail:
    {{ lhs() }} ;;
    {{ rhs() }} ;;
    HALT ;;
