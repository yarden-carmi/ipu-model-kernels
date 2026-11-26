{# Broadcast one input lane across a tile of output channels. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mac(slot, scalar, first=false) %}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro pair(scalar, first=false, more=false) %}
    {{ mac('LR0', scalar, first) }} ; {{ load('LR1') }} ; INC LR3 1 ;;
    {{ mac('LR1', scalar) }}{% if more %} ; {{ load('LR0') }} ; BLT.S LR3 LR7 lane{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
{% set max_pack = [1, 128 // in0_d3] | max %}
{% set pack = max_pack if in0_d2 % max_pack == 0 and 128 % in0_d3 == 0 else 1 %}
{% set aligned = k % 128 == 0 and in0_d3 * pack % 128 == 0 %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ; SET LR12 {{ cr.width }} ;;
{% if not aligned %}
    SET LR11 CR0 ; SET LR15 CR0 ;;
    DEC LR11 1 ;;
{% endif %}
    DEC LR12 1 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
{% if aligned %}
    SET LR2 LR8 ; SET LR9 {{ cr.chunks }} ;;
    DEC LR2 1 ; {{ load('LR0') }} ;;
    {{ pair('CR1', first=true) }}
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ;;
    SET LR3 CR0 ; SET LR7 LR12 ; BNE LR9 CR0 prepare ;;
    SET LR7 {{ cr.last }} ;;
prepare:
    {{ load('LR0') }} ; DEC LR3 1 ; BEQ LR7 CR0 last_lane ;;
    DEC LR7 1 ;;
lane:
    {{ pair('LR3', more=true) }}
last_lane:
    {{ pair('LR3') }}
    BNE LR9 CR0 chunk ;;
{% else %}
    {# Track the flattened view across stored-row padding. A tile starts
       at the same physical input position as the preceding tile. #}
    SET LR2 LR8 ; SET LR7 LR15 ; SET LR9 LR14 ;;
    {{ load('LR0') }} ;;
    {{ pair('CR1', first=true) }}
    SET LR3 LR11 ;;
scalar:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ load('LR0') }} ; SET LR13 LR12 ; BNE LR7 {{ cr.block_last_row }} scalar_mac ;;
    SET LR13 {{ cr.block_last_lane }} ;;
scalar_mac:
    {{ pair('LR3') }}
    DEC LR9 1 ; BLT.S LR3 LR13 scalar_next ;;
    INC LR2 1 ; INC LR7 1 ; SET LR3 CR0 ;;
    DEC LR3 1 ; BLT.S {{ cr.block_last_row }} LR7 reset_block ;;
    B scalar_next ;;
reset_block:
    SET LR7 CR0 ;;
scalar_next:
    BNE LR9 CR0 scalar ;;
{% endif %}
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
{% if aligned %}
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ;;
{% else %}
    SET LR8 LR2 ; SET LR11 LR3 ; SET LR15 LR7 ;;
    DEC LR10 1 ;;
{% endif %}
    BNE LR10 CR0 row ;;
    HALT ;;
