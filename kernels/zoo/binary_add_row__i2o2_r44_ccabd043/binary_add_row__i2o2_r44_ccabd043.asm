{% macro add_row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ; INC LR1 1 ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR3 1 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    INC LR2 128 ; SET LR5 CR0 ; SET LR6 CR0 ;;
batch:
    SET LR7 {{ cr.in0_d1 }} ;;
plane:
    ADD LR1 LR6 CR0 ; SET LR8 {{ cr.in0_d3 }} ;;
column:
    SET LR4 {{ cr.full_chunks }} ; BEQ {{ cr.full_chunks }} CR0 tail ;;
chunk:
    {{ add_row(cr.full ~ '.L') }}
    DEC LR4 1 ;;
    BNE LR4 CR0 chunk ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    ADD LR1 LR1 {{ cr.column_skip }} ; DEC LR8 1 ;;
    BNE LR8 CR0 column ;;
    BEQ LR5 {{ cr.rows }} done ;;
    BLT.S LR3 LR10 next_plane ;;
    SET LR3 CR0 ;;
next_plane:
    ADD LR6 LR6 LR11 ; DEC LR7 1 ;;
    BNE LR7 CR0 plane ;;
    ADD LR6 LR6 {{ cr.batch_skip }} ; B batch ;;
done:
    HALT ;;
