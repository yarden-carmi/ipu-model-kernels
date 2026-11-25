{% macro store_row(index) %}
    MULT.RC.VE {{ index }} CR1 0 LR0 {{ cr.input_active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.output_active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
{% endmacro %}

    SET LR2 CR0 ;;
    SET LR3 CR0 ;;
pair:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {{ store_row("LR0") }}
    INC LR3 1 ;;
    {# Start at the second vector; the store zeroes lanes beyond its channel count. #}
    {{ store_row("LR1") }}
    INC LR3 1 ;;
    INC LR2 1 ; BLT.S LR2 {{ cr.last_pair }} pair ;;
    HALT ;;
