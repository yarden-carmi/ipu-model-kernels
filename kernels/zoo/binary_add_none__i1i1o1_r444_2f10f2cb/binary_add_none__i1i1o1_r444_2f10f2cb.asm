{% macro add_row(mask) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; BGE.S LR5 {{ cr.last_row }} last ;;
row:
    {{ add_row(cr.active) }}
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.last_row }} row ;;
last:
    {{ add_row(cr.last_active) }}
    HALT ;;
