{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
plane:
    ADD LR2 LR1 {{ cr.full_rows }} ;;
    BEQ LR1 LR2 tail ;;
row:
    {{ add_row(cr.active) }}
    BNE LR1 LR2 row ;;
tail:
    {{ add_row(cr.tail) }}
    BNE LR1 {{ cr.rows }} plane ;;
    HALT ;;
