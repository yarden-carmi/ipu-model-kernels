{# A stays in R0; successive B rows each supply an N tile for one k. #}
{% macro product(first) %}
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ; DEC LR9 1 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR7 LR7 {{ cr.strides }}.H ; BEQ LR9 CR0 write ;;
    INC.MODP2 LR8 CR1 7 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ;;
    INC LR14 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ; SET LR15 {{ cr.heads }}.H ;;
group:
    SET LR13 {{ cr.heads }}.L ; SET LR3 CR0 ;;
head:
    SET LR4 {{ cr.m }} ; SET LR5 LR1 ;;
row:
    SET LR6 {{ cr.tiles }} ;;
tile:
    SET LR7 {{ cr.tiles }} ; SET LR8 LR3 ; SET LR9 {{ cr.k }} ;;
    SUB LR7 LR7 LR6 ; SET LR12 LR5 ;;
    ADD LR7 LR7 LR2 ;;
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
write:
    DEC LR6 1 ;;
    BEQ LR6 CR0 tail ;;
    {{ store('L') }}
    B tile ;;
tail:
    {{ store('H') }}
    ADD LR5 LR5 {{ cr.strides }}.L ; DEC LR4 1 ;;
    BNE LR4 CR0 row ;;
    SET LR12 {{ cr.tiles }} ; ADD LR3 LR3 {{ cr.k }} ; DEC LR13 1 ;;
    DEC LR12 1 ;;
    SUB LR2 LR7 LR12 ; SET LR12 CR0 ;;
    INC LR12 128 ;;
normalize:
    BLT.S LR3 LR12 head_ready ;;
    DEC LR3 128 ; INC LR1 1 ; B normalize ;;
head_ready:
    BNE LR13 CR0 head ;;
    ADD LR1 LR1 LR10 ; ADD LR2 LR2 LR11 ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
