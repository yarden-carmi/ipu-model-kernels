{# Broadcast one A lane over an N tile of B. #}
{% macro step(first) %}
    LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR0 ; DEC LR12 1 ;;
    MULT.RC.VE LR0 LR11 0 LR0 {{ cr.dso }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR10 LR10 {{ cr.bstride }} ; BEQ LR12 CR0 tile_done ;;
    INC.MODP2 LR11 CR1 7 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dso }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
group:
    SET LR14 LR2 ; SET LR3 CR0 ; SET LR6 {{ cr.rows_heads }}.H ;;
head:
    SET LR8 LR14 ; SET LR7 {{ cr.rows_heads }}.L ;;
row:
    SET LR9 CR0 ;;
tile:
    ADD LR10 LR4 LR9 ; SET LR11 LR3 ; SET LR12 {{ cr.k }} ;;
    SET LR13 LR8 ;;
    LD.MULT R0 LR13 {{ cr.in0 }} ;;
    {{ step(true) }}
    BNE LR11 CR0 reduce ;;
reload:
    INC LR13 1 ;;
    LD.MULT R0 LR13 {{ cr.in0 }} ;;
reduce:
    {{ step(false) }}
    BNE LR11 CR0 reduce ;;
    B reload ;;
tile_done:
    INC LR9 1 ;;
    BEQ LR9 {{ cr.bstride }} last_tile ;;
    {{ store('L') }}
    B tile ;;
last_tile:
    {{ store('H') }}
    ADD LR8 LR8 {{ cr.astride }} ; DEC LR7 1 ;;
    BNE LR7 CR0 row ;;
    DEC LR9 1 ; ADD LR3 LR3 {{ cr.k }} ; DEC LR6 1 ;;
    SUB LR4 LR10 LR9 ;;
    BEQ LR6 CR0 group_done ;;
normalize:
    BLT.S LR3 LR15 head ;;
    DEC LR3 128 ; INC LR14 1 ; B normalize ;;
group_done:
    ADD LR2 LR2 {{ cr.agroup }} ; DEC LR5 1 ;;
    BNE LR5 CR0 group ;;
    HALT ;;
