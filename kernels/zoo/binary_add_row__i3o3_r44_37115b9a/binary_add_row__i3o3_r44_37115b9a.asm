{# Keep one folded row resident in R1 while visiting its broadcast planes. #}
{% macro start_sum() %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ADD LR4 LR1 CR0
{% endmacro %}
{% macro finish_sum() %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR2 128 ;;
row:
    LD.MULT R1 LR3 {{ cr.operand }} ; SET LR1 LR3 ; SET LR5 CR0 ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.last_plane }} CR0 final_plane ;;
plane:
    {{ start_sum() }} ; ADD LR1 LR1 {{ cr.period }} ;;
    {{ finish_sum() }} ; LD.MULT R0 LR1 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.period }} ; BLT.S LR5 {{ cr.penultimate_plane }} plane ;;
final_plane:
    {{ start_sum() }} ;;
    {{ finish_sum() }} ; INC LR3 1 ; BLT.S LR3 {{ cr.last_row }} row ;;
    HALT ;;
