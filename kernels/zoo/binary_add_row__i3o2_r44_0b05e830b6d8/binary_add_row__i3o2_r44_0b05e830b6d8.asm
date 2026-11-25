{% macro scatter() %}
    MULT.EE LR5 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ;;
batch:
    SET LR5 CR0 ; BEQ {{ cr.per_group }} CR0 shared_batch ;;
    BEQ CR0 CR0 column ;;
shared_batch:
    SET LR12 CR0 ;;
column:
    SET LR6 CR0 ; SET LR7 LR4 ;;
group:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 LR7 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
    SET LR9 {{ cr.remaining }} ; BEQ {{ cr.remaining }} CR0 last ;;
    {{ scatter() }} ; INC LR8 1 ; LD.MULT R0 LR8 {{ cr.in0 }} ; BEQ LR9 CR1 last_advance ;;
    DEC LR9 1 ;;
gather:
    {{ scatter() }} ; ADDBI LRD2 1 ; INC LR8 1 ; LD.MULT R0 LR8 {{ cr.in0 }} ; DEC LR9 1 ; BNE LR9 CR1 gather ;;
last_advance:
    ADDBI LRD2 1 ;;
last:
    {{ scatter() }} ; LD.MULT R0 LR12 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ; INC LR6 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ; ADD LR12 LR12 {{ cr.per_group }} ;;
    INC LR11 1 ; BNE LR6 {{ cr.in0_d1 }} group ;;
    INC LR5 1 ; BNE {{ cr.per_group }} CR0 next_column ;;
    INC LR12 1 ;;
next_column:
    BNE LR5 {{ cr.in0_d3 }} column ;;
    SET LR4 LR7 ; BNE LR11 {{ cr.out_rows }} batch ;;
    HALT ;;
