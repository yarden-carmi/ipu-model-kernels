{% macro store_row(active) %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}

    SET LR2 CR0 ;;
plane:
    SET LR3 CR0 ; BEQ {{ cr.last_chunk }} CR0 tail ;;
full_row:
    {{ store_row(cr.full) }}
    INC LR2 1 ; INC LR3 1 ;;
    BNE LR3 {{ cr.last_chunk }} full_row ;;
tail:
    {{ store_row(cr.tail) }}
    INC LR2 1 ;;
    BNE LR2 {{ cr.out_rows }} plane ;;
    HALT ;;
