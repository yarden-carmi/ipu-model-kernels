{# Stream paired high and residual weight rows for each broadcast input lane. #}
{% macro load(slot) %}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }}
{% endmacro %}
{% macro mac(slot, scalar, first=false) -%}
    MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro pair(scalar, first=false, repeat=false) %}
    {{ mac('LR0', scalar, first) }} ; {{ load('LR1') }}{% if not first %} ; INC LR3 1{% endif %} ;;
    {{ mac('LR1', scalar) }}{% if repeat %} ; {{ load('LR0') }} ; BLT.S LR3 LR7 lane_loop{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SUB LR2 LR8 CR1 ;;
    {{ load('LR0') }} ; SET LR9 {{ cr.chunks }} ;;
    {{ pair('CR1', first=true) }}
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ;;
    SET LR3 CR0 ; SET LR7 {{ cr.full_end }} ; BNE LR9 CR0 lane ;;
    SET LR7 {{ cr.end }} ;;
lane:
    DEC LR3 1 ;;
    {{ load('LR0') }} ; DEC LR7 1 ; BLT.S LR7 CR0 last_lane ;;
lane_loop:
    {{ pair('LR3', repeat=true) }}
last_lane:
    {{ pair('LR3') }}
    BNE LR9 CR0 chunk ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
