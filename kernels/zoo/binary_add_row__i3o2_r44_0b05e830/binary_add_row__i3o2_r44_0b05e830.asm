{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR6 CR0 ;;
    SET LR13 CR0 ;;
batch:
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR7 LR6 ;;
column:
    SET LR8 LR7 ; SET LR11 {{ cr.out0_d1 }} ;;
channel:
    SET LR9 LR8 ; SET LR12 {{ cr.oc }} ;;
tile:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
    DEC LR12 1 ;;
    INC LR10 128 ; BNE LR12 CR0 gather ;;
    SET LR10 {{ cr.tail }} ;;
gather:
    # Scatter the selected column from successive input rows into one output row.
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR9 LR9 {{ cr.ic }} ; DEC LR10 1 ;;
    ADDBI LRD2 1 ; BNE LR10 CR0 gather ;;
    LD.MULT R0 LR13 {{ cr.operand }} ; BEQ LR12 CR0 last_tile ;;
    {{ add_store(full) }}
    B tile ;;
last_tile:
    {{ add_store(tail) }}
    BEQ LR13 {{ cr.rows }} done ;;
    ADD LR8 LR8 {{ cr.plane_rows }} ; DEC LR11 1 ;;
    BNE LR11 CR0 channel ;;
    INC LR5 1 ; INC.MODP2 LR4 CR1 7 ;;
    BEQ LR5 {{ cr.out0_d3 }} next_batch ;;
    BNE LR4 CR0 column ;;
    INC LR7 1 ; B column ;;
next_batch:
    # LR8 includes the input chunk of the last column. Remove it before rebasing.
    SUB LR7 LR7 LR6 ;;
    SUB LR6 LR8 LR7 ; B batch ;;
done:
    HALT ;;
