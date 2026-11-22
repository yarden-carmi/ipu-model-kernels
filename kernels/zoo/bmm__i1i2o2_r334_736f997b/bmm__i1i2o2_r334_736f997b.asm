{% macro product(first) %}
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; DEC LR9 1 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR7 LR7 {{ cr.reduce_tiles }}.H ; BEQ LR9 CR0 tile_done ;;
    INC.MODP2 LR14 CR1 7 ;;
{% endmacro %}
{% macro output_store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}

    SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR13 CR0 ;;
group:
    SET LR0 CR0 ; SET LR1 LR11 ; SET LR2 LR10 ;;
    SET LR3 CR0 ; SET LR15 {{ cr.out0_d1 }} ;;
head:
    SET LR4 {{ cr.n }} ; SET LR5 LR1 ;;
column:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR14 LR3 ; SET LR9 {{ cr.reduce_tiles }}.L ;;
    SET LR12 LR5 ;;
    LD.MULT R0 LR12 {{ cr.in1 }} ;;
    {{ product(true) }}
    BNE LR14 CR0 reduce ;;
reload:
    INC LR12 1 ;;
    LD.MULT R0 LR12 {{ cr.in1 }} ;;
reduce:
    {{ product(false) }}
    BNE LR14 CR0 reduce ;;
    B reload ;;
tile_done:
    INC LR6 1 ;;
    BEQ LR6 {{ cr.reduce_tiles }}.H last_tile ;;
    {{ output_store('L') }}
    B tile ;;
last_tile:
    {{ output_store('H') }}
    ADD LR5 LR5 {{ cr.b_stride }} ; DEC LR4 1 ;;
    BNE LR4 CR0 column ;;
    DEC LR15 1 ; DEC LR6 1 ; ADD LR3 LR3 {{ cr.reduce_tiles }}.L ;;
    BEQ LR15 CR0 group_done ;;
    SUB LR2 LR7 LR6 ; SET LR7 CR0 ;;
    INC LR7 128 ;;
normalize:
    BLT.S LR3 LR7 head ;;
    DEC LR3 128 ; INC LR1 1 ;;
    B normalize ;;
group_done:
    ADD LR10 LR10 {{ cr.a_group }} ; ADD LR11 LR11 {{ cr.b_group }} ; DEC LR8 1 ;;
    BNE LR8 CR0 group ;;
    HALT ;;
