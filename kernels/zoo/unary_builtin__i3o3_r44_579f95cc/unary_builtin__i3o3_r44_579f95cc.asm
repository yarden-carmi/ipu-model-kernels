{% macro store_row() %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}
    SET LR2 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S {{ cr.penultimate }} CR0 tail ;;
row:
    {{ store_row() }}
    INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.penultimate }} row ;;
tail:
    {{ store_row() }}
    HALT ;;
