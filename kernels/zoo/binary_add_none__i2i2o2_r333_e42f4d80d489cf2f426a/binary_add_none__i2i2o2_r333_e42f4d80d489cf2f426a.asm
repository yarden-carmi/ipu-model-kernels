{% macro finish(mask) %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;
    BLT.S LR1 LR4 loop ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR4 {{ cr.rows }} ;;
    SUB LR1 LR0 CR1 ; SET LR2 CR0 ; SET LR3 CR1 ;;
    INC LR2 128 ; SUB LR4 LR4 CR1 ;;
loop:
    INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;
    LD.MULT R1 LR1 {{ cr.in1 }} ; INC LR3 1 ; BLT.S LR3 {{ cr.width }} full ;;
    SET LR3 CR1 ; {{ finish(cr.tail ~ '.L') }}
    HALT ;;
full:
    {{ finish('CR15.L') }}
    HALT ;;
