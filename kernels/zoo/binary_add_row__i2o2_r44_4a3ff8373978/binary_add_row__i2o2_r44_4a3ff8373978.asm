{% macro add_chunk(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR3 1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR5 CR1 ;;
batch:
    SET LR6 CR0 ;;
column:
    SET LR7 {{ cr.in0_d1 }} ;;
channel:
    SET LR3 LR6 ; SET LR4 {{ cr.chunks }} ; BEQ {{ cr.chunks }} LR5 tail ;;
chunk:
    {{ add_chunk(cr.full ~ '.L') }}
    DEC LR4 1 ;;
    BNE LR4 LR5 chunk ;;
tail:
    {{ add_chunk(cr.tail ~ '.L') }}
    DEC LR7 1 ;;
    BNE LR7 CR0 channel ;;
    SET LR6 LR3 ;;
    BLT.S LR6 {{ cr.plane_rows }} column ;;
    BLT.S LR1 {{ cr.rows }} batch ;;
    HALT ;;
