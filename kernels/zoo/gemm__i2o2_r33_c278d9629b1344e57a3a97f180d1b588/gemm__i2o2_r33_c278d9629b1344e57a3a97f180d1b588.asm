{# Broadcast each input lane into one output vector. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mac(slot, scalar, first=false) -%}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro dot(scalar, repeat=false) %}
    {{ mac('LR0', scalar) }} ; INC LR3 1{% if repeat %} ; {{ load('LR0') }} ; BLT.S LR3 LR7 loop_lane{% endif %} ;;
{% endmacro %}
{% macro refined_dot(scalar, first=false, repeat=false) %}
    {{ mac('LR0', scalar, first) }} ; {{ load('LR1') }}{% if not first %} ; INC LR3 1{% endif %} ;;
    {{ mac('LR1', scalar) }}{% if repeat %} ; {{ load('LR0') }} ; BLT.S LR3 LR7 refined_lane{% endif %} ;;
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
    SET LR2 LR8 ; SET LR9 {{ cr.chunks }} ;;
    DEC LR2 1 ;;
    {{ load('LR0') }} ;;
    SET LR11 {{ cr.refined }} ;;
    {{ refined_dot('CR1', true) }}
    BEQ LR11 CR0 chunk ;;
refined_chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ; DEC LR11 1 ;;
    SET LR3 CR0 ; SET LR7 {{ cr.full_end }} ;;
    {{ load('LR0') }} ; DEC LR3 1 ; DEC LR7 1 ;;
refined_lane:
    {{ refined_dot('LR3', repeat=true) }}
    {{ refined_dot('LR3') }}
    BNE LR11 CR0 refined_chunk ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ;;
    SET LR3 CR0 ; SET LR7 {{ cr.full_end }} ; BNE LR9 CR0 lane ;;
    SET LR7 {{ cr.end }} ;;
lane:
    DEC LR3 1 ;;
    {{ load('LR0') }} ; DEC LR7 1 ; BEQ LR7 CR0 last_lane ;;
    DEC LR7 1 ;;
loop_lane:
    {{ dot('LR3', repeat=true) }}
last_lane:
    {{ dot('LR3') }}
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
