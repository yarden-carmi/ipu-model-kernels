{% macro add_row(mask) %}
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ mask }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ mask }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; BEQ {{ cr.tail_lanes }} CR0 uniform ;;
    BEQ {{ cr.full_chunks }} CR0 uniform ;;
pixel:
    SET LR6 {{ cr.full_chunks }} ;;
full:
    {{ add_row(cr.full_mask) }}
    DEC LR6 1 ;;
    BNE LR6 CR0 full ;;
    {{ add_row(cr.tail_mask) }}
    BLT.S LR5 {{ cr.rows }} pixel ;;
    HALT ;;
uniform:
    {{ add_row(cr.tail_mask) }}
    BLT.S LR5 {{ cr.rows }} uniform ;;
    HALT ;;
