{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro store(ds) %}
    MULT.VE LR14 CR1 0 LR14 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR8 1 ;;
    INC LR3 1 ;;
{% endmacro %}

    SET LR0 {{ cr.in0_d0 }} ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR14 CR0 ;;
batch:
    SET LR5 CR0 ; SET LR11 CR0 ;;
column:
    SET LR9 LR1 ; SET LR2 {{ cr.in0_d1 }} ;;
head:
    SET LR10 LR9 ; SET LR8 LR5 ; SET LR7 {{ cr.oc }} ;;
tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR4 LR10 ;;
    SET LR6 LR15 ; BEQ LR7 CR1 gather ;;
    SET LR6 CR0 ;;
    INC LR6 128 ;;
gather:
    # Broadcast the chosen input column, then scatter one copy.
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.EE LR11 CR1 0 LR14 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD12 7 ; ADD LR4 LR4 {{ cr.ic }} ; DEC LR6 1 ;;
    ADDBI LRD12 1 ; BNE LR6 CR0 gather ;;
    LD.MULT R0 LR8 {{ cr.operand }} ; SET LR10 LR4 ; BEQ LR7 CR1 last_tile ;;
    {{ store(full) }}
    DEC LR7 1 ; B tile ;;
last_tile:
    {{ store(tail) }}
    ADD LR9 LR9 {{ cr.plane_rows }} ; DEC LR2 1 ;;
    BNE LR2 CR0 head ;;
    ADD LR5 LR5 {{ cr.oc }} ; INC.MODP2 LR11 CR1 7 ;;
    BEQ LR5 {{ cr.operand_rows }} next_batch ;;
    BNE LR11 CR0 column ;;
    INC LR1 1 ; B column ;;
next_batch:
    ADD LR1 LR1 {{ cr.batch_skip }} ; DEC LR0 1 ;;
    BNE LR0 CR0 batch ;;
    HALT ;;
