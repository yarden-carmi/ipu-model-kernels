{% macro add_row(ds) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    LD.MULT R1 LR5 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR4 1 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR1 CR0 ; SET LR4 CR0 ; SET LR9 CR0 ;;
    INC LR2 128 ;;
batch:
    SET LR5 CR0 ; SET LR7 CR0 ;;
position:
    SET LR3 {{ cr.blocks }} ;;
block:
    DEC LR3 1 ;;
    BEQ LR3 CR0 tail ;;
    {{ add_row('CR15.L') }}
    B block ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.out0_d1 }} position ;;
    SET LR6 CR0 ;;
padloop:
    BGE.S LR6 {{ cr.skip }} padend ;;
    ACTIVATE.QUANTIZE identity {{ cr.none }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR6 1 ;;
    B padloop ;;
padend:
    INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d0 }} batch ;;
    HALT ;;
