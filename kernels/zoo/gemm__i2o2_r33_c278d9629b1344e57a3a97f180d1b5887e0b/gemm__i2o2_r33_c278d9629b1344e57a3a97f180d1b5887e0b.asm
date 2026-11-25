{# Broadcast each input lane into one output vector. #}
{% macro load(slot) %}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }}
{% endmacro %}
{% macro mac(slot, scalar, first=false) -%}
MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro dot(scalar, repeat=false) %}
    {{ mac('LR0', scalar) }} ; INC LR3 1{% if repeat %} ; {{ load('LR0') }} ; BLT.S LR3 LR7 loop_lane{% else %} ; BNE LR9 CR0 chunk{% endif %} ;;
{% endmacro %}
{% macro refined_dot(scalar, first=false, repeat=false, target='refined_lane', drain=false) %}
    {{ mac('LR0', scalar, first) }} ; {{ load('LR1') }}{% if not first %} ; INC LR3 1{% endif %} ;;
    {{ mac('LR1', scalar) }}{% if repeat %} ; {{ load('LR0') }} ; BLT.S LR3 LR7 {{ target }}{% elif drain %} ; BNE LR9 CR0 chunk_full{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
{% macro gemm_loop(suffix, exact) %}
row{{ suffix }}:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile{{ suffix }}:
    SUB LR2 LR8 CR1 ;;
    {{ load('LR0') }} ; SET LR9 {{ cr.chunks }}{% if not exact %} ; SET LR11 {{ cr.refined }}{% endif %} ;;
    {{ refined_dot('CR1', true) }}
    {% if not exact %}
    BEQ LR11 CR0 skip_pairs ;;
refined_chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ; DEC LR11 1 ;;
    SET LR3 CR0 ; SET LR7 {{ cr.full_end }} ;;
    {{ load('LR0') }} ; DEC LR3 1 ; DEC LR7 1 ;;
refined_lane:
    {{ refined_dot('LR3', repeat=true) }}
    {{ refined_dot('LR3') }}
    BNE LR11 CR0 refined_chunk ;;
skip_pairs:
    ADD LR4 LR4 LR15 ;;
    {% endif %}
chunk{{ suffix }}:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ;;
    SET LR3 CR0 ; SET LR7 {{ cr.full_end }} ; BNE LR9 CR0 lane{{ suffix }} ;;
    SET LR7 {{ cr.end }} ;;
lane{{ suffix }}:
    DEC LR3 1 ;;
    {{ load('LR0') }} ; DEC LR7 1 ; BLT.S LR7 CR0 last_lane{{ suffix }} ;;
    {% if not exact %}
    DEC LR7 1 ;;
loop_lane:
    {{ dot('LR3', repeat=true) }}
    {% else %}
loop_lane{{ suffix }}:
    {{ refined_dot('LR3', repeat=true, target='loop_lane' ~ suffix) }}
    {% endif %}
last_lane{{ suffix }}:
    {% if exact %}
    {{ refined_dot('LR3', drain=true) }}
    {% else %}
    {{ dot('LR3') }}
    {% endif %}
    DEC LR6 1{% if exact %} ; ADD LR4 LR4 LR14{% endif %} ;;
    BEQ LR6 CR0 last_tile{{ suffix }} ;;
    {{ store(cr.full) }}
    B tile{{ suffix }} ;;
last_tile{{ suffix }}:
    {{ store(cr.tail) }}
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ;;
    BNE LR10 CR0 row{{ suffix }} ;;
    HALT ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 {{ cr.width }} ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ; BEQ LR13 CR1 row ;;
    BEQ LR14 CR0 row_full ;;
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
    BNE {{ cr.qf_in0 }}.L LR12 scan_raw_tile ;;
    BNE {{ cr.qf_out0 }}.L LR12 scan_raw_tile ;;
{# Read the alternate encoding once, outside the row loop. #}
{% macro scan_tail(raw) %}
scan_{{ 'raw' if raw else 'pairs' }}_tile:
    ADD LR4 LR4 LR11 ; SET LR7 {{ 'LR14' if raw else 'LR15' }} ; DEC LR6 1 ;;
    {% if raw %}ADD LR4 LR4 LR15 ;;{% endif %}
scan_{{ 'raw' if raw else 'pairs' }}:
    {{ load('LR0') }} ; DEC LR7 1 ; BLT.S CR1 LR7 scan_{{ 'raw' if raw else 'pairs' }} ;;
    {% if not raw %}ADD LR4 LR4 LR14 ;;{% endif %}
    BNE LR6 CR0 scan_{{ 'raw' if raw else 'pairs' }}_tile ;;
{% endmacro %}
    {{ scan_tail(false) }}
    {{ gemm_loop('', false) }}
    {{ scan_tail(true) }}
    {{ gemm_loop('_full', true) }}
