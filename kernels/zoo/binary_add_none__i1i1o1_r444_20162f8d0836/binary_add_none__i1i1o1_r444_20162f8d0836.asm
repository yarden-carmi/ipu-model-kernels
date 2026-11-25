{% macro add_row(rhs) %}
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE {{ rhs }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    INC LR1 128 ; SET LR4 CR0 ;;
pair:
    // Keep both RHS items in R1 and select each by its lane offset.
    LD.MULT R1 LR4 {{ cr.in1 }} ;;
    {{ add_row('LR1') }}
    BEQ LR3 {{ cr.rows }} done ;;
    {{ add_row('LR2') }}
    INC LR4 1 ; BLT.S LR3 {{ cr.rows }} pair ;;
done:
    HALT ;;
