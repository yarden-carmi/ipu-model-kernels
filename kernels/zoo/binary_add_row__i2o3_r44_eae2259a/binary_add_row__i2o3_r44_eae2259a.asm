{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity', true) }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR13 CR0 ; SET LR11 {{ cr.out0_d1 }} ;;
head:
    SET LR8 LR7 ; SET LR4 CR0 ; SET LR5 {{ cr.out0_d2 }} ;;
row:
    SET LR9 LR8 ; SET LR12 {{ cr.oc }} ;;
tile:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 CR0 ;;
    DEC LR12 1 ;;
    INC LR10 128 ; BNE LR12 CR0 gather ;;
    SET LR10 {{ cr.tail }} ;;
gather:
    # Successive input columns contribute one lane each to the output row.
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR9 LR9 {{ cr.stride }} ; DEC LR10 1 ;;
    ADDBI LRD2 1 ; BNE LR10 CR0 gather ;;
    LD.MULT R0 LR13 {{ cr.operand }} ; BEQ LR12 CR0 last_tile ;;
    {{ add_store(full) }}
    B tile ;;
last_tile:
    {{ add_store(tail) }}
    BEQ LR13 {{ cr.rows }} done ;;
    DEC LR5 1 ; INC.MODP2 LR4 CR1 7 ;;
    BEQ LR5 CR0 next_head ;;
    BNE LR4 CR0 row ;;
    INC LR8 1 ; B row ;;
next_head:
    DEC LR11 1 ; ADD LR7 LR7 {{ cr.ic }} ;;
    BNE LR11 CR0 head ;;
    # LR9 is the next batch base plus this head and lane-chunk offset.
    SUB LR9 LR9 LR8 ; SET LR11 {{ cr.out0_d1 }} ;;
    SUB LR7 LR7 {{ cr.stride }} ;;
    ADD LR7 LR7 LR9 ; B head ;;
done:
    HALT ;;
