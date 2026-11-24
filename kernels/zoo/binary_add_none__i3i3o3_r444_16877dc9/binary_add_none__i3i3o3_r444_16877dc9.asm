// All tensors share the producer's width-packed row order.
{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
plane:
    SET LR2 CR0 ;;
tile:
    BEQ LR2 {{ cr.before_tail }} last_tile ;;
    {{ add_row(cr.active) }}
    INC LR2 1 ; B tile ;;
last_tile:
    {{ add_row(cr.tail) }}
    BLT.S LR1 {{ cr.rows }} plane ;;
    HALT ;;
