{% macro compute() %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{% endmacro %}
    SET LR2 CR0 ; SET LR3 {{ cr.minus_one }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.last_row }} row ;;
    BEQ LR2 CR0 tail ;;
row:
    {# The load uses the incremented pointer; the branch compares the old pointer. #}
    {{ compute() }} ; INC LR2 1 ; INC LR3 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.penultimate }} row ;;
tail:
    {{ compute() }} ; INC LR3 1 ;;
    HALT ;;
