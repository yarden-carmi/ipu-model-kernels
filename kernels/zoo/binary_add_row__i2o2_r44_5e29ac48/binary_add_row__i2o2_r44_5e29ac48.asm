{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR3 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR3 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR2 CR0 ;;
    INC LR2 128 ;;
column:
    SET LR4 {{ cr.full }} ;;
    BEQ LR4 CR0 tail ;;
full:
    {{ add_row('CR15.L') }}
    DEC LR4 1 ;;
    BNE LR4 CR0 full ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    BLT.S LR3 {{ cr.period }} column ;;
    SET LR3 CR0 ;;
    BLT.S LR1 {{ cr.rows }} column ;;
    HALT ;;
