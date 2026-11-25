{# Read sequentially in [batch, head, column] order, scattering whole
   lane chunks to [batch, column, head] order. #}
{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ; INC LR1 1 ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR3 1 ;;
    INC LR4 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR3 CR0 ; SET LR10 CR0 ;;
batch:
    SET LR7 LR10 ; SET LR9 {{ cr.in0_d1 }} ;;
head:
    SET LR6 LR7 ; SET LR8 {{ cr.in0_d3 }} ;;
column:
    SET LR4 LR6 ; SET LR5 {{ cr.chunks }} ; BEQ {{ cr.chunks }} CR1 tail ;;
chunk:
    {{ add_row(cr.full ~ '.L') }}
    DEC LR5 1 ;;
    BNE LR5 CR1 chunk ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    ADD LR6 LR6 {{ cr.column_stride }} ; DEC LR8 1 ;;
    BNE LR8 CR0 column ;;
    BEQ LR1 {{ cr.rows }} done ;;
    BLT.S LR3 {{ cr.operand_rows }} next_head ;;
    SET LR3 CR0 ;;
next_head:
    ADD LR7 LR7 {{ cr.chunks }} ; DEC LR9 1 ;;
    BNE LR9 CR0 head ;;
    ADD LR10 LR10 LR11 ; B batch ;;
done:
    HALT ;;
