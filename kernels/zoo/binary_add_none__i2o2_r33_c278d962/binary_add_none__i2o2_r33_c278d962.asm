{% macro add_row(mask) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.constant }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_constant }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
row:
{% if out0_d2 % 128 == 0 %}
    {{ add_row('CR15') }}
    INC LR1 1 ;;
{% else %}
    BEQ LR2 {{ cr.last_chunk }} tail ;;
    {{ add_row('CR15') }}
    INC LR2 1 ; INC LR1 1 ; B row ;;
tail:
    {{ add_row(cr.tail) }}
    SET LR2 CR0 ; INC LR1 1 ;;
{% endif %}
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
