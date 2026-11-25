{# Broadcast a query feature across a contiguous tile of key tokens. #}
{% macro mac(first) -%}
    MULT.RC.VE LR0 LR15 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;
{%- endmacro %}
{% macro load_b() -%}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;
{%- endmacro %}
{% macro product(first) %}
    {{ load_b() }} ;;
    {{ mac(first) }} DEC LR12 1 ; ADD LR9 LR9 {{ cr.tiles }} ;;
{% endmacro %}
{# With 16-aligned heads, a block never crosses an A row. Consume B
   before replacing its cyclic slot; peel the last load to stay in bounds. #}
{% macro block(first, check) %}
    {{ load_b() }} ;;
    {% for i in range(16) %}
    {{ mac(first and i == 0) }} ADD LR9 LR9 {{ cr.tiles }} ; {% if i > 0 %}INC.MODP2 LR15 CR1 7 ; {% endif %}{% if i < 15 %}{{ load_b() }} {% endif %};;
    {% endfor %}
    INC.MODP2 LR15 CR1 7 ; DEC LR12 16 ; BNE LR15 CR0 {{ check }} ;;
    INC LR11 1 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsfull }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ;;
head:
    SET LR7 LR1 ; SET LR8 CR0 ;;
row:
    SET LR10 CR0 ;;
tile:
    ADD LR9 LR3 LR10 ; SET LR11 LR7 ; SET LR12 {{ cr.k }} ;;
    SET LR15 LR2 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ; BNE {{ cr.k_tail16 }} CR0 generic ;;
    {{ block(true, 'first_check') }}
first_check:
    BEQ LR12 CR0 store_tile ;;
more_blocks:
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    {{ block(false, 'block_check') }}
block_check:
    BNE LR12 CR0 more_blocks ;;
    B store_tile ;;
generic:
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    BEQ LR12 CR0 store_tile ; INC.MODP2 LR15 CR1 7 ;;
    BNE LR15 CR0 inner ;;
    INC LR11 1 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    B inner ;;
store_tile:
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.tiles }} full ;;
    {{ store('H') }}
    ADD LR7 LR7 {{ cr.arows }} ; INC LR8 1 ; INC LR4 1 ;;
    BLT.S LR8 {{ cr.m }} row ;;
    INC LR5 1 ;;
    BEQ LR5 {{ cr.b }} done ;;
    SUB LR3 LR9 LR10 ; INC LR6 1 ; ADD LR2 LR2 {{ cr.k }} ;;
    INC LR3 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
normalize:
    BLT.S LR2 LR11 normalized ;;
    SUB LR2 LR2 LR11 ; INC LR1 1 ;;
    B normalize ;;
normalized:
    BLT.S LR6 {{ cr.out0_d1 }} head ;;
    ADD LR1 LR1 LR14 ; ADD LR3 LR3 LR13 ; SET LR6 CR0 ;;
    SET LR2 CR0 ;;
    B head ;;
full:
    {{ store('L') }}
    INC LR4 1 ;;
    B tile ;;
done:
    HALT ;;
