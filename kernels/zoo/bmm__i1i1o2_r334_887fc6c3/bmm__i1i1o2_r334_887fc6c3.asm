{# Each stored row is one head/reduction coordinate, with tokens in lanes.
   Broadcast one RHS token and accumulate a vector of LHS tokens. #}
{% macro mac(first) %}
    LD.MULT R0 LR12 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR14 ; DEC LR13 1 ;;
    MULT.RC.VE LR14 LR5 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR11 LR11 {{ cr.tiles }}.L ; ADD LR12 LR12 {{ cr.tiles }}.H ; BEQ LR13 CR0 store ;;
{% endmacro %}
{% macro output(half) %}
    INC LR0 1 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ;;
    DEC LR0 1 ;;
group:
    SET LR3 {{ cr.columns_heads }}.L ; SET LR4 CR0 ; SET LR5 CR0 ;;
column:
    SET LR6 {{ cr.columns_heads }}.H ; SET LR7 LR1 ; ADD LR8 LR2 LR4 ;;
head:
    SET LR9 {{ cr.tiles }}.L ; SET LR10 LR7 ;;
tile:
    SET LR11 LR10 ; SET LR12 LR8 ; SET LR13 {{ cr.k }} ;;
    {{ mac(true) }}
reduce:
    {{ mac(false) }}
    B reduce ;;
store:
    DEC LR9 1 ; BEQ LR9 CR1 tail ;;
    {{ output('L') }}
    INC LR10 1 ; B tile ;;
tail:
    {{ output('H') }}
    ADD LR7 LR7 {{ cr.head_steps }}.L ; ADD LR8 LR8 {{ cr.head_steps }}.H ; DEC LR6 1 ; BNE LR6 CR1 head ;;
    DEC LR3 1 ; BEQ LR3 CR1 next_group ;;
    INC.MODP2 LR5 CR1 7 ;;
    BNE LR5 CR0 column ;;
    INC LR4 1 ; B column ;;
next_group:
    SET LR1 LR7 ; SUB LR2 LR8 LR4 ; DEC LR15 1 ; BNE LR15 CR1 group ;;
    HALT ;;
