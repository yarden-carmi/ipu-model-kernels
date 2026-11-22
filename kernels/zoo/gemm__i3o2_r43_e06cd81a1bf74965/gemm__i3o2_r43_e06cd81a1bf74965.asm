{# LR8:LR9 is the merge cursor (physical row, logical lane minus one).
   Restart each output tile from that cursor and skip physical padding. #}
{% macro load_weight(slot) -%}
LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1
{%- endmacro %}
{% macro mac(slot, scalar, first=false) -%}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro dot(scalar, first=false) %}
    {{ load_weight('LR0') }}{% if not first %} ; INC LR3 1 ; DEC LR7 1{% endif %} ;;
{% for p in range(3) %}
    {{ mac('LR1' if p % 2 else 'LR0', scalar, first and p == 0) }}{% if p < 2 %} ; {{ load_weight('LR0' if p % 2 else 'LR1') }}{% elif not first %} ; BNE LR3 LR11 lane{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.slot }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 {{ cr.rows }} ;;
    DEC LR9 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR9 ; SET LR7 {{ cr.k }} ;;
    {{ dot('CR1', true) }}
load_input:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR11 LR3 LR7 ;;
    BLT.S LR11 {{ cr.last_lane }} lane ;;
    SET LR11 {{ cr.last_lane }} ;;
lane:
    {{ dot('LR3') }}
    BEQ LR3 {{ cr.last_lane }} next_input ;;
    B store_tile ;;
next_input:
    INC LR2 1 ; SET LR3 CR0 ;;
    DEC LR3 1 ; BNE LR7 CR0 load_input ;;
store_tile:
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    INC LR5 1 ; B tile ;;
last_tile:
    {{ store(cr.tail) }}
    INC LR5 1 ; SET LR8 LR2 ; SET LR9 LR3 ;;
    DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
