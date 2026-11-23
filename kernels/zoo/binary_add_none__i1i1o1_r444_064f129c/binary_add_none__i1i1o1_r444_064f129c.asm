{% macro add_store(active) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ;;
row:
    SET LR6 CR0 ;;
    BEQ LR6 {{ cr.full }} tail ;;
full:
    {{ add_store('CR15') }}
    INC LR6 1 ; BLT.S LR6 {{ cr.full }} full ;;
tail:
    {{ add_store(cr.tail) }}
    BLT.S LR5 {{ cr.rows }} row ;;
    HALT ;;
