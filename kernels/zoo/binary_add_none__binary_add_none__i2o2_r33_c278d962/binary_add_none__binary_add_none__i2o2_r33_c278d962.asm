{% macro store_row(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR3 CR0 ;;
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.c0 }} ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_c0 }}.L ; ACC.ADD ; LD.MULT R0 LR1 {{ cr.c1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_c1 }}.L ; ACC.ADD ;;
{% if in0_d2 % 128 %}
    BLT.S LR3 {{ cr.last_chunk }} full ;;
    {{ store_row(cr.tail) }}
    SET LR3 CR0 ; BEQ LR0 CR0 next ;;
full:
{% endif %}
    {{ store_row('CR15') }}
{% if in0_d2 % 128 %}
    INC LR3 1 ;;
next:
{% endif %}
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
