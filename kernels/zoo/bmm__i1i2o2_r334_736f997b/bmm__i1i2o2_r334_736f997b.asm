{% macro store(tensor, half, qf, cursor, act='identity') %}
    ACTIVATE.QUANTIZE {{ act }} {{ cr.ds }}.{{ half }} {{ qf }}.L {{ tensor }} {{ cursor }} ;;
    INC {{ cursor }} 1 ;;
{% endmacro %}

{% macro product(first) %}
    LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR6 ; DEC LR14 1 ;;
    MULT.RC.VE LR6 LR15 0 LR6 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR12 LR12 {{ cr.tiles }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR6 CR0 ;;
group:
    SET LR3 CR0 ; SET LR8 LR5 ;;
head:
    SET LR9 {{ cr.n }} ; SET LR10 LR1 ;;
column:
    SET LR11 CR0 ;;
tile:
    ADD LR12 LR2 LR11 ; SET LR13 LR10 ; SET LR14 {{ cr.k }} ;;
    SET LR15 LR3 ;;
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    {{ product(true) }}
    B advance ;;
reduce:
    {{ product(false) }}
advance:
    BEQ LR14 CR0 reduced ; INC.MODP2 LR15 CR1 7 ;;
    BNE LR15 CR0 reduce ;;
    INC LR13 1 ;;
    LD.MULT R0 LR13 {{ cr.in1 }} ;;
    B reduce ;;
reduced:
    INC LR11 1 ;;
    BEQ LR11 {{ cr.tiles }} tail ;;
    {{ store(cr.out0, 'L', cr.qf_out0, 'LR0', act_out0 | default('identity')) }}
    B tile ;;
tail:
    {{ store(cr.out0, 'H', cr.qf_out0, 'LR0', act_out0 | default('identity')) }}
    ADD LR10 LR10 {{ cr.bc }} ; DEC LR9 1 ;;
    BNE LR9 CR0 column ;;
    // LR12 ends just past the head, plus the index of the last tile.
    DEC LR11 1 ; ADD LR3 LR3 {{ cr.k }} ; SUB LR8 LR8 {{ cr.k }} ;;
    SUB LR2 LR12 LR11 ; SET LR13 CR0 ;;
    INC LR13 128 ;;
normalize:
    BLT.S LR3 LR13 normalized ;;
    SUB LR3 LR3 LR13 ; INC LR1 1 ;;
    B normalize ;;
normalized:
    BNE LR8 CR0 head ;;
    ADD LR1 LR1 LR7 ; ADD LR2 LR2 {{ cr.a_delta }} ; DEC LR4 1 ;;
    BNE LR4 CR0 group ;;
    HALT ;;
