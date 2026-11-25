{% macro add_row() %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR3 CR0 ; BNE {{ cr.unshared }} CR0 unshared ;;
batch:
    SET LR3 CR0 ;;
column:
    ADD LR4 LR1 {{ cr.in0_d1 }} ;;
channel:
    {{ add_row() }}
    BLT.S LR1 LR4 channel ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.in0_d3 }} column ;;
    BLT.S LR1 {{ cr.rows }} batch ;;
    HALT ;;
unshared:
    {{ add_row() }}
    INC LR3 1 ;;
    BLT.S LR1 {{ cr.rows }} unshared ;;
    HALT ;;
