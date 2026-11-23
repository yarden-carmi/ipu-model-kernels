{% macro add_row(ds, prefetch) %}
    INC LR5 1 ; LD.MULT R1 LR1 {{ cr.in1 }} ; MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    INC LR1 1 ; MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5
    {% if prefetch %}
    ; INC LR3 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR3 {{ cr.repeat }} full
    {% else %}
    ; BLT.S LR5 {{ cr.last }} group
    {% endif %}
    ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SUB LR5 LR0 CR1 ; INC LR2 128 ; SET LR4 {{ cr.repeat }} ;;
group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR4 CR0 tail ;;
full:
    {{ add_row('CR15', true) }}
tail:
    {{ add_row(cr.tail, false) }}
    HALT ;;
