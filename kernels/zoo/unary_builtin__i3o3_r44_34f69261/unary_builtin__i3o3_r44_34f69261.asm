{% macro store_row(ds) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endmacro %}

    SET LR2 CR0 ;;
plane:
    SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BEQ CR0 {{ cr.full_rows }} tail ;;
full:
    {{ store_row(cr.active) }}
    INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.full_rows }} full ;;
tail:
    {{ store_row(cr.tail_active) }}
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.out_rows }} plane ;;
    HALT ;;
