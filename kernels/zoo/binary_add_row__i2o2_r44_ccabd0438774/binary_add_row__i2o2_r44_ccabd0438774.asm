{% macro add_row(ds) %}
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ; INC LR4 1 ;;
    MULT.VE LR2 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR3 1 ;;
    INC LR1 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR3 CR0 ; SET LR6 CR0 ;;
    SET LR5 CR1 ;;
batch:
    SET LR8 {{ cr.in0_d1 }} ;;
plane:
    SET LR4 LR6 ; SET LR7 {{ cr.in0_d3 }} ;;
column:
    SET LR9 {{ cr.chunks }} ; BEQ {{ cr.chunks }} LR5 tail ;;
chunk:
    {{ add_row(cr.full ~ '.L') }}
    DEC LR9 1 ;;
    BNE LR9 LR5 chunk ;;
tail:
    {{ add_row(cr.tail ~ '.L') }}
    ADD LR4 LR4 {{ cr.column_gap }} ; DEC LR7 1 ;;
    BNE LR7 CR0 column ;;
    ADD LR6 LR6 {{ cr.chunks }} ; SUB LR3 LR3 LR13 ; DEC LR8 1 ;;
    BNE LR8 CR0 plane ;;
    ADD LR6 LR6 LR12 ;;
    BNE LR1 {{ cr.rows }} batch ;;
    HALT ;;
