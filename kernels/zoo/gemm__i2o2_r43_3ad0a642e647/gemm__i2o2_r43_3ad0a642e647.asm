{# LR2/LR3/LR7/LR13 traverse the physical row, d2, d3 and scalar lane. #}
{% macro load(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro dot(scalar, first=false) %}
{% if not first %}
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
{% endif %}
    {{ load('LR0') }} ;;
{% for i in range(4) %}
    MULT.RC.VE {{ 'LR0' if i % 2 == 0 else 'LR1' }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ (cr.qf_w if first else cr.qf_in0) }}.L ; ACC.ADD{% if first and loop.first %}.FIRST{% endif %}{% if not loop.last %} ; {{ load('LR1' if i % 2 == 0 else 'LR0') }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR11 CR0 ;;
    SET LR12 CR0 ; SET LR15 CR0 ; DEC LR5 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR11 ; SET LR7 LR12 ;;
    SET LR13 LR15 ; SET LR9 {{ cr.k }} ;;
    {{ dot('CR1', first=true) }}
feature:
    {{ dot('LR13') }}
    ADD LR2 LR2 {{ cr.chunks }} ; INC LR7 1 ; DEC LR9 1 ;;
    BNE LR7 {{ cr.in0_d3 }} advanced ;;
    SET LR7 CR0 ; INC LR3 1 ; INC.MODP2 LR13 CR1 7 ;;
    BEQ LR3 {{ cr.in0_d2 }} next_plane ;;
    SUB LR2 LR2 LR14 ; BNE LR13 CR0 advanced ;;
    INC LR2 1 ; B advanced ;;
next_plane:
    SET LR3 CR0 ; SET LR13 CR0 ; SUB LR2 LR2 {{ cr.chunk_pad }} ;;
advanced:
    BNE LR9 CR0 feature ;;
    DEC LR6 1 ; BEQ LR6 CR1 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR8 LR2 ; SET LR11 LR3 ; SET LR12 LR7 ;;
    SET LR15 LR13 ; DEC LR10 1 ; BNE LR10 CR1 row ;;
    HALT ;;
