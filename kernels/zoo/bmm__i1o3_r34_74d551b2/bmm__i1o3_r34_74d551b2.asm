{# Each input row holds tokens for one projected channel. One query
   scalar feeds an entire tile of key tokens without a scratch transpose. #}
{# Consume the current pair before replacing R0. The next word replaces
   the cyclic operand, so both loads are ready at the next product. #}
{% macro product(first, preload, jump='') %}
    MULT.RC.VE LR15 LR5 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; {% if preload %}ADD LR10 LR10 {{ cr.stride }} ; LD.MULT R0 LR10 {{ cr.in0 }} ; DEC LR12 1 ; {% endif %}{% if jump %}B {{ jump }} ; {% endif %};;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}

group:
    SET LR3 {{ cr.out0_d1 }} ;;
head:
    ADD LR2 LR1 {{ cr.key_offset }} ; SET LR5 CR0 ; SET LR6 LR1 ;;
    SET LR7 {{ cr.m }} ;;
query:
    SET LR8 LR2 ; SET LR9 {{ cr.tiles }} ;;
tile:
    SET LR10 LR6 ; SET LR11 LR8 ; SET LR12 {{ cr.k }} ;;
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ; BEQ LR12 CR1 single ;;
    {{ product(true, true) }}
next_key:
    ADD LR11 LR11 {{ cr.stride }} ; LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR15 ; BNE LR12 CR1 reduce ;;
    {{ product(false, false) }}
write:
    DEC LR9 1 ;;
    BEQ LR9 CR0 tail ;;
    {{ store('L') }}
    INC LR8 1 ; B tile ;;
tail:
    {{ store('H') }}
    INC.MODP2 LR5 CR1 7 ; DEC LR7 1 ;;
    BNE LR5 CR0 query_check ;;
    INC LR6 1 ;;
query_check:
    BNE LR7 CR0 query ;;
    ADD LR1 LR1 {{ cr.head_rows }} ; DEC LR3 1 ;;
    BNE LR3 CR0 head ;;
    ADD LR1 LR1 {{ cr.group_gap }} ; DEC LR4 1 ;;
    BNE LR4 CR0 group ;;
    HALT ;;
reduce:
    {{ product(false, true, 'next_key') }}
single:
    {{ product(true, false, 'write') }}
