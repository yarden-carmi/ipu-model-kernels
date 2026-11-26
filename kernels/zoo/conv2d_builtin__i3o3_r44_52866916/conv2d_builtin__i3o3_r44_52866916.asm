{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}

{# Fold zeros the weights on invalid spatial lanes. An out-of-plane
   cyclic load can therefore safely use the first block instead. #}
{% macro load_block(tag, delta, slot) %}
    SUB LR4 LR7 LR8 ; SET LR3 LR8 ;;
{% if delta %}
    {{ 'INC' if delta > 0 else 'DEC' }} LR3 {{ delta | abs }} ;;
{% endif %}
{% if delta < 0 %}
    BLT.S LR3 CR0 edge_{{ tag }} ;;
{% endif %}
    BGE.S LR3 {{ cr.in_chunks }} edge_{{ tag }} ;;
    ADD LR4 LR4 LR3 ;;
edge_{{ tag }}:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} {{ slot }} ;;
{% endmacro %}

{% macro load_weight() %}LD.MULT R0 LR5 {{ cr.weights }} ; INC LR5 1{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
{% endmacro %}

{% macro tap(ky, kx) %}
{% set offset = (ky-padding)*in0_d3 + kx-padding %}
{% set rem = offset % 128 %}
    {{ load_block(ky ~ '_' ~ kx ~ '_a', offset // 128, 'LR0') }}
{% if rem %}
    {{ load_block(ky ~ '_' ~ kx ~ '_b', offset // 128 + 1, 'LR1') }}
    SET LR2 CR0 ;;
    INC LR2 {{ rem }} ;;
{% endif %}
    {{ load_weight() }} ;;
{% for digit in range(3) %}
    MULT.RC.VV {{ 'LR2' if rem else 'LR0' }} R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD{% if not loop.last %} ; {{ load_weight() }}{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR6 CR0 ; SET LR10 CR0 ;;
    SET LR12 {{ cr.groups }} ; DEC LR5 1 ;;
group:
    SET LR11 {{ cr.group_out }} ;;
channel:
    SET LR8 CR0 ;;
block:
    ADD LR7 LR6 LR8 ; SET LR9 {{ cr.group_in }} ;;
    {{ load_weight() }} ;;
{% for digit in range(3) %}
    MULT.VE LR0 CR1 0 LR0 {{ full }} {{ qi }} ; ACC.ADD{{ '.FIRST' if loop.first else '' }}{% if not loop.last %} ; {{ load_weight() }}{% endif %} ;;
{% endfor %}
input_channel:
{% for ky in range(kh) %}
{% for kx in range(kw) %}
    {{ tap(ky, kx) }}
{% endfor %}
{% endfor %}
    ADD LR7 LR7 {{ cr.in_chunks }} ; DEC LR9 1 ;;
    BLT.S LR0 LR9 input_channel ;;
    BEQ LR8 {{ cr.last_block }} tail ;;
    {{ store(full) }}
    B stored ;;
tail:
    {{ store(cr.tail ~ '.L') }}
stored:
    INC LR8 1 ; INC LR10 1 ;;
    BLT.S LR8 {{ cr.out_chunks }} block ;;
    DEC LR11 1 ;;
    BLT.S LR0 LR11 channel ;;
    ADD LR6 LR6 {{ cr.group_span }} ; DEC LR12 1 ;;
    BLT.S LR0 LR12 group ;;
    HALT ;;
