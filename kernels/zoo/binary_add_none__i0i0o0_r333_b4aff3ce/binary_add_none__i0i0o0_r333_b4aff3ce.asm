{% macro add_store(mask) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

// Both inputs and the output share the same packed lane order.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
row:
    BGE.S LR2 {{ cr.last }} tail ;;
    {{ add_store(cr.full) }}
    INC LR2 1 ; INC LR1 1 ; B row ;;
tail:
    {{ add_store(cr.tail) }}
    SET LR2 CR0 ; INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
