{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR3 CR0 ;;

// Both inputs use the output's channel-lane order. Decode each in its own QF.
row:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.blocks }} full ;;
    {{ store(cr.tail ~ '.L') }}
    SET LR3 CR0 ; B advance ;;
full:
    {{ store('CR15.L') }}
advance:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} row ;;
    HALT ;;
