{# Each packed activation row provides two heads' worth of K scalars.
   Stream weight planes through a single cyclic slot, one word ahead. #}
{% macro next_weight() %}
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ; INC LR6 1
{%- endmacro %}
{% macro mac(scalar, first=false) %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ next_weight() }}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{%- endmacro %}
{% set bias_scalar = 'CR1' if bias else 'CR0' %}
    SET LR14 {{ cr.rows }} ;;
row:
    SET LR9 {{ cr.tiles }} ; SET LR6 CR0 ;;
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
tile:
    SET LR1 LR10 ; SET LR4 {{ cr.groups }} ;;
    {{ mac(bias_scalar, true) }} ;;
    {{ mac(bias_scalar) }} ;;
group:
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR2 CR0 ;;
    DEC LR2 1 ;;
reduction:
    {{ mac('LR2') }} ; INC LR2 1 ;;
    {{ mac('LR2') }} ; BLT.S LR2 {{ cr.group_last }} reduction ;;
    INC LR1 1 ; DEC LR4 1 ; BNE LR4 CR1 group ;;
    DEC LR9 1 ; BEQ LR9 CR1 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    SET LR10 LR1 ; DEC LR14 1 ; BNE LR14 CR1 row ;;
    HALT ;;
