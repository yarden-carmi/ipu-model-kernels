{% macro add_input(offset, mode) %}
    MULT.VE {{ offset }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ mode }}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ; SET LR6 CR0 ;;
    INC LR5 64 ; INC LR6 128 ;;
period:
    SET LR3 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
{% if in0_d3 == 64 %}
    {{ add_input('LR0', '.FIRST') }} ; LD.MULT R1 LR1 {{ cr.in0 }} ; INC LR1 1 ;;
    // The window from lane 64 contains the first row's padding and the second row's data.
    {{ add_input('LR5', '') }} ; LD.MULT R1 LR3 {{ cr.operand }} ;;
{% else %}
    {{ add_input('LR0', '.FIRST') }} ; LD.MULT R1 LR3 {{ cr.operand }} ;;
{% endif %}
    MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR1 1 ; INC LR3 1 ;;
    INC LR2 1 ;;
    BEQ LR2 {{ cr.out_rows }} done ;;
    BLT.S LR3 {{ cr.period }} row ;;
    B period ;;
done:
    HALT ;;
