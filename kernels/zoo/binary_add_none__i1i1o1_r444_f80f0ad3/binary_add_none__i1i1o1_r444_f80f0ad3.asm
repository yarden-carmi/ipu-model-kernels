{% macro load_pair() %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR4 {{ cr.in1 }} ;;
{% endmacro %}
{% macro add_row(lhs, rhs) %}
    MULT.VE {{ lhs }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE {{ rhs }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    BGE.S LR4 {{ cr.pairs }} tail ;;
pair:
    {{ load_pair() }}
    {{ add_row('LR0', 'LR2') }}
    {{ add_row('LR1', 'LR3') }}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.pairs }} pair ;;
tail:
    BGE.S LR5 {{ cr.rows }} done ;;
    {{ load_pair() }}
    {{ add_row('LR0', 'LR2') }}
done:
    HALT ;;
