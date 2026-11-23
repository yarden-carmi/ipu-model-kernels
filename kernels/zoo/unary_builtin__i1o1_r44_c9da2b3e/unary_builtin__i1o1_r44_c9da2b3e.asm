{% macro relu_row(ds) %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    SET LR2 CR0 ;;
    BEQ LR2 {{ cr.last }} tail ;;
row:
    {{ relu_row(cr.full) }}
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.last }} row ;;
tail:
    {{ relu_row(cr.tail) }}
    HALT ;;
