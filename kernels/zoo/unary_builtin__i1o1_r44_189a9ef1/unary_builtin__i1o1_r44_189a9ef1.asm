{% macro compute(ds) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{% endmacro %}
    SET LR2 CR0 ; SET LR3 CR0 ;;
row:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BEQ LR3 {{ cr.last_tile }} partial ;;
    {{ compute(cr.active) }} ;;
    INC LR2 1 ; INC LR3 1 ; BEQ LR0 CR0 row ;;
partial:
    {{ compute(cr.tail_active) }} ; BEQ LR2 {{ cr.last_row }} done ;;
    INC LR2 1 ; SET LR3 CR0 ; BEQ LR0 CR0 row ;;
done:
    HALT ;;
