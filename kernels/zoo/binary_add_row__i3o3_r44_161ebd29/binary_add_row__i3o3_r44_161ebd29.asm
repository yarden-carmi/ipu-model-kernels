{# Load each packed input row once; select each half at the multiplier. #}
{% macro add_row(start, next_label) %}
    MULT.VE {{ start }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR3 1 ;;
    INC LR4 1 ; BLT.S LR3 {{ cr.period }} {{ next_label }} ;;
    SET LR3 CR0 ;;
{{ next_label }}:
{% endmacro %}

    INC LR2 128 ; INC LR5 64 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ add_row('LR0', 'first_done') }}
{% if in0_d3 == 64 %}
    BLT.S LR4 {{ cr.rows }} second ;;
    HALT ;;
second:
    {{ add_row('LR5', 'second_done') }}
{% endif %}
    INC LR1 1 ; BLT.S LR4 {{ cr.rows }} row ;;
    HALT ;;
