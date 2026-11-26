{% macro add_item(packed_lane) %}
    LD.MULT R1 LR5 {{ cr.in0 }} ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE {{ packed_lane }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
    INC LR2 128 ; SET LR5 CR0 ; SET LR3 {{ cr.in1_d1 }} ;;
pair:
    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    {{ add_item('LR0') }}
    BGE.S LR5 {{ cr.rows }} done ;;
    {{ add_item('LR3') }}
    INC LR4 1 ; BLT.S LR5 {{ cr.rows }} pair ;;
done:
    HALT ;;
