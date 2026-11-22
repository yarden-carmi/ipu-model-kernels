{% macro product(first) %}
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; DEC LR9 1 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR7 LR7 {{ cr.strides }}.H ; BEQ LR9 CR0 tile_done ;;
    INC.MODP2 LR8 CR1 7 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR15 CR0 ; SET LR14 {{ cr.out0_d0 }} ;;
group:
    SET LR1 LR15 ; SET LR2 LR11 ; SET LR3 CR0 ;;
    SET LR13 {{ cr.reduce_heads }}.H ;;
head:
    SET LR4 {{ cr.rows_tiles }}.L ; SET LR5 LR1 ;;
row:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR8 LR3 ; SET LR9 {{ cr.reduce_heads }}.L ;;
    SET LR12 LR5 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ product(true) }}
    BNE LR8 CR0 reduce ;;
reload:
    INC LR12 1 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
reduce:
    {{ product(false) }}
    BNE LR8 CR0 reduce ;;
    B reload ;;
tile_done:
    INC LR6 1 ;;
    BEQ LR6 {{ cr.rows_tiles }}.H last_tile ;;
    {{ store('L') }}
    B tile ;;
last_tile:
    {{ store('H') }}
    ADD LR5 LR5 {{ cr.strides }}.L ; DEC LR4 1 ;;
    BNE LR4 CR0 row ;;
    DEC LR13 1 ; ADD LR3 LR3 {{ cr.reduce_heads }}.L ; ADD LR2 LR2 {{ cr.b_head }} ;;
    BEQ LR13 CR0 group_done ;;
    SET LR8 CR0 ;;
    INC LR8 128 ;;
normalize:
    BLT.S LR3 LR8 head ;;
    DEC LR3 128 ; INC LR1 1 ;;
    B normalize ;;
group_done:
    ADD LR15 LR15 {{ cr.a_group }} ; ADD LR11 LR11 {{ cr.b_group }} ; DEC LR14 1 ;;
    BNE LR14 CR0 group ;;
    HALT ;;
