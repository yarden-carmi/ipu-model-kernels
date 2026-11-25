{% macro store_window(index) %}
    MULT.RC.VE {{ index }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ;;
{% endmacro %}

    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
pair:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    # Initialize the entire shifted window; the store discards its upper lanes.
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR4 ;;
    {{ store_window('LR0') }}
    {{ store_window('LR3') }}
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.in_rows }} pair ;;
    HALT ;;
