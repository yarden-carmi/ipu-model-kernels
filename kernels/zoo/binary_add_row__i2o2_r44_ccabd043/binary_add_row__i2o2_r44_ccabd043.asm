{# At fixed batch, column, and chunk, input heads are one padded column
   apart, while output heads are one plane apart. Reuse the constant row. #}
{% macro add_heads(ds, label) %}
    ADD LR5 LR7 LR3 ; SET LR6 {{ cr.heads }} ; LD.MULT R1 LR3 {{ cr.operand }} ;;
    SET LR1 LR8 ;;
{{ label }}:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ADD LR1 LR1 {{ cr.chunks }} ; DEC LR6 1 ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    ADD LR5 LR5 {{ cr.period }} ; BNE LR6 CR0 {{ label }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR8 CR0 ; SET LR2 CR0 ;;
    SET LR7 CR0 ;;
    INC LR2 128 ;;
batch:
    SET LR3 CR0 ;;
column:
    SET LR4 {{ cr.full }} ;;
    BEQ LR4 CR0 tail ;;
full:
    {{ add_heads('CR15.L', 'full_heads') }}
    DEC LR4 1 ; INC LR3 1 ; INC LR8 1 ;;
    BNE LR4 CR0 full ;;
tail:
    {{ add_heads(cr.tail ~ '.L', 'tail_heads') }}
    INC LR3 1 ; SUB LR8 LR1 {{ cr.full }} ;;
    BLT.S LR3 {{ cr.period }} column ;;
    ADD LR7 LR7 {{ cr.batch_rows }} ;;
    BLT.S LR7 {{ cr.rows }} batch ;;
    HALT ;;
