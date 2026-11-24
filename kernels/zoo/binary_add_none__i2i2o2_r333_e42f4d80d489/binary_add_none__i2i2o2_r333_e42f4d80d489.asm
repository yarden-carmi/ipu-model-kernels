{% macro load_and_start() %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR1 {{ cr.in1 }} ;;
{% endmacro %}
{% macro finish(mask) %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ mask }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
    SET LR3 CR0 ;;
    BEQ LR0 {{ cr.remainder }} aligned ;;

{# Only unaligned shapes need a per-row tail check. #}
partial:
    {{ load_and_start() }}
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.width }} full ;;
    {{ finish(cr.tail ~ '.L') }}
    SET LR3 CR0 ;;
    BEQ LR0 CR0 next ;;
full:
    {{ finish('CR15.L') }}
next:
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} partial ;;
    HALT ;;

aligned:
    {{ load_and_start() }}
    {{ finish('CR15.L') }}
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} aligned ;;
    HALT ;;
