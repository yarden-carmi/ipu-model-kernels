{# Each RHS row holds two adjacent columns, at lane 0 and lane in1_d1.
   LR9 tracks that lane base across heads; only the group boundary resets it.
   The A vectors and accumulators already have the output M-lane order. #}
{% macro mac(first) %}
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR14 ; INC LR3 1 ;;
    MULT.RC.VE LR14 LR3 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR12 1 ; ADD LR8 LR8 {{ cr.m_and_tiles }}.H ;;
{% endmacro %}

{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ;;
{% endmacro %}

    INC LR15 128 ;;
group:
    SET LR7 LR1 ; SET LR9 CR0 ;;
    SET LR4 {{ cr.in0_d1 }} ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    LD.MULT R0 LR7 {{ cr.in1 }} ; SET LR2 LR0 ; SET LR6 {{ cr.m_and_tiles }}.L ;;
tile:
    SET LR8 LR2 ; SET LR3 LR9 ; SET LR12 {{ cr.k_and_pitch }}.L ;;
    DEC LR3 1 ;;
    {{ mac(true) }}
    BEQ LR12 CR0 store ;;
key:
    {{ mac(false) }}
    BNE LR12 CR0 key ;;
store:
    BGT.S LR6 LR15 full ;;
    {{ output('H') }}
    BEQ LR9 CR0 upper ;;
    SET LR9 CR0 ; INC LR7 1 ; B next_column ;;
upper:
    SET LR9 {{ cr.k_and_pitch }}.H ;;
next_column:
    DEC LR5 1 ; BGT.S LR5 CR1 column ;;
    ADD LR0 LR0 {{ cr.a_head_step }} ; DEC LR4 1 ; BGT.S LR4 CR1 head ;;
    ADD LR1 LR1 {{ cr.rhs_group_step }} ; DEC LR11 1 ; BGT.S LR11 CR1 group ;;
    HALT ;;
full:
    {{ output('L') }}
    DEC LR6 128 ; INC LR2 1 ; B tile ;;
