{% macro start_row() %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.in1 }} ;;
{% endmacro %}
{% macro finish_row(ds) %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR3 CR0 ;;
    BEQ {{ cr.padding }} CR0 aligned ;;

padded:
    {{ start_row() }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.width }} full ;;
    {{ finish_row(cr.tail) }}
    SET LR3 CR0 ;;
    B next_row ;;
full:
    {{ finish_row('CR15') }}
next_row:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} padded ;;
    HALT ;;

aligned:
    {{ start_row() }}
    {{ finish_row('CR15') }}
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} aligned ;;
    HALT ;;
