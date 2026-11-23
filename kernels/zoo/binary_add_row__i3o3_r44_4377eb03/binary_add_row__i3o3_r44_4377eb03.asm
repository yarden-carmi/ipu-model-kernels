{# LR1 is the output row, LR4 the prefetched input row, LR3 the operand row. #}
{% macro sum_row(prefetch) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
    {% if prefetch %}
    LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; INC LR3 1 ; INC LR1 1 ; BLT.S LR3 {{ cr.penultimate_operand }} row ;;
    {% else %}
    INC LR1 1 ; BLT.S LR4 {{ cr.last_row }} plane ;;
    {% endif %}
{% endmacro %}
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR4 CR0 ;;
    DEC LR1 1 ; INC LR2 128 ; DEC LR4 1 ;;
plane:
    SET LR3 CR0 ; LD.MULT R0 LR4 {{ cr.in0 }} ; INC LR4 1 ; BLT.S CR0 {{ cr.last_operand }} row ;;
    B last ;;
row:
    {{ sum_row(true) }}
last:
    {{ sum_row(false) }}
    HALT ;;
