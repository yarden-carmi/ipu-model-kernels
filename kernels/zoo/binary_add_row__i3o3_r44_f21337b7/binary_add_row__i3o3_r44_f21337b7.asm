{# A physical row holds a group of adjacent logical rows in both operands.
   Advance LR1 for the prefetch, keeping the packed store offset in LR4. #}
{% macro add_input() %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ; ADD LR4 LR1 CR0 ; INC LR1 1 ;;
{% endmacro %}
{% macro finish_sum() %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
plane:
    SET LR3 CR0 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ {{ cr.last_row }} CR0 plane_tail ;;
row:
    {{ add_input() }}
    {{ finish_sum() }} ; LD.MULT R0 LR1 {{ cr.in0 }} ; INC LR3 1 ; BLT.S LR3 {{ cr.penultimate_row }} row ;;
plane_tail:
    {# The last row does not prefetch beyond the plane. #}
    {{ add_input() }}
    {{ finish_sum() }} ; BLT.S LR1 {{ cr.rows }} plane ;;
    HALT ;;
