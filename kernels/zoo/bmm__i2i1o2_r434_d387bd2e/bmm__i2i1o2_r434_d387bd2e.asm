{# A vectors and accumulators both use the output M-lane order.
   LR7 points to the RHS pair, LR9 selects its column, and LR14/LR3
   walk the physical rows/lanes of that column during reduction. #}
{% macro mac(first) %}
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR10 ; DEC LR12 1 ;;
    MULT.RC.VE LR10 LR3 0 LR10 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR8 LR8 {{ cr.m_tiles }}.H ; BEQ LR12 CR0 store ;;
    INC LR3 1 ;;
{% endmacro %}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR10 CR0 ; SET LR13 CR0 ;;
group:
    SET LR7 LR1 ; SET LR9 {{ cr.pair_info }}.H ; SET LR4 {{ cr.n_heads }}.H ;;
head:
    SET LR5 {{ cr.n_heads }}.L ;;
column:
    SET LR2 LR0 ; SET LR6 {{ cr.m_tiles }}.L ;;
tile:
    SET LR8 LR2 ; SET LR12 {{ cr.k_limit }}.L ; SET LR14 LR7 ;;
    SET LR3 CR0 ; BEQ LR9 CR0 first ;;
    ADD LR14 LR7 {{ cr.odd_start }}.L ; SET LR3 {{ cr.odd_start }}.H ;;
first:
    LD.MULT R0 LR14 {{ cr.in1 }} ;;
    {{ mac(true) }}
    BNE LR3 {{ cr.k_limit }}.H reduce ;;
wrap:
    INC LR14 1 ; SET LR3 CR0 ;;
    LD.MULT R0 LR14 {{ cr.in1 }} ;;
reduce:
    {{ mac(false) }}
    BNE LR3 {{ cr.k_limit }}.H reduce ;;
    B wrap ;;
store:
    BGT.S LR6 {{ cr.k_limit }}.H full ;;
    {{ output('H') }}
    BEQ LR9 CR0 odd ;;
    SET LR9 CR0 ; ADD LR7 LR7 {{ cr.pair_info }}.L ; B next_column ;;
odd:
    SET LR9 CR1 ;;
next_column:
    DEC LR5 1 ;;
    BNE LR5 CR0 column ;;
    ADD LR0 LR0 {{ cr.a_head_step }} ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.rhs_group_step }} ; DEC LR11 1 ;;
    BNE LR11 CR0 group ;;
    HALT ;;
full:
    {{ output('L') }}
    DEC LR6 128 ; INC LR2 1 ; B tile ;;
