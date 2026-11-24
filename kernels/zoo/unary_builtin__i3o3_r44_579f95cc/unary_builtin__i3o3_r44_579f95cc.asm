{% macro compute() %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.input_active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}

    SET LR2 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.last_row }} row ;;
    BEQ LR2 CR0 tail ;;
row:
    {{ compute() }} ;;
    {# Load the next row; the branch compares the pre-increment index. #}
    INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR2 {{ cr.penultimate }} row ;;
tail:
    {{ compute() }} ;;
    HALT ;;
