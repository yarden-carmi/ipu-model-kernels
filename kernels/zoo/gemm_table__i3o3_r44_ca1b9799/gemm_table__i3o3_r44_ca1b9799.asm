{% set w = in0_d3 %}
{% set in_capacity = [in0_d2, 128 // w] | min %}
{% set in_pack = in_capacity if in0_d2 % in_capacity == 0 else 1 %}
{% set capacity = 128 // out0_d3 %}
{% set out_pack = capacity if out0_d1 % capacity == 0 else 1 %}
{% set ds = cr.active ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set expand = in_pack > 1 or out_pack > 1 %}
{% set spatial = cr.repeated if expand else cr.in0 %}
{% macro scatter(skip) %}
    MULT.VE LR4 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 {{ skip }}
{%- endmacro %}
{% macro mac(bias=false, first=false) %}
    {% if bias %}MULT.RC.VE LR4 CR1 0 LR4{% else %}MULT.RC.VV LR4 R0 0 LR4{% endif %} {{ ds }} {{ qi }} ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro next_coeff() %}
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4
{%- endmacro %}

    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
{% if expand %}
{# Expand each packed spatial slice across the output channels in a tile. #}
unpack:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR8 {{ cr.src_lo }} ; SET LR9 {{ cr.src_hi }} ; SET LR10 CR0 ;;
    INC LR10 {{ in_pack }} ;;
slice:
    SET LR2 {{ cr.src_lo }} ; SET LR3 {{ cr.src_hi }} ; SET LR7 CR0 ;;
    INC LR7 {{ out_pack }} ;;
broadcast:
    SET LR0 LR8 ; SET LR1 LR9 ;;
{% for i in range(w // 8) %}
    {{ scatter(0) }} ;;
    ADDBI LRD0 8 ; ADDBI LRD2 8 ;;
{% endfor %}
{% if w % 8 %}
    ADDBI LRD0 {{ w % 8 - 8 }} ; ADDBI LRD2 {{ w % 8 - 8 }} ;;
    {{ scatter(8 - w % 8) }} ;;
    ADDBI LRD2 8 ;;
{% endif %}
    DEC LR7 1 ; BNE LR7 CR1 broadcast ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.repeated }} LR6 ; ADDBI LRD8 {{ w }} ; DEC LR10 1 ;;
    INC LR6 1 ; BNE LR10 CR0 slice ;;
    INC LR5 1 ;;
    BNE LR5 {{ cr.input_rows }} unpack ;;
{% endif %}

    SET LR6 CR0 ; SET LR5 CR0 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR6 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR6 ;;
{% endfor %}
    SET LR6 CR0 ;;
batch:
    SET LR14 {{ cr.in0_d2 }} ;;
stripe:
    SET LR8 CR0 ; SET LR9 {{ cr.tiles }} ;;
tile:
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ; SET LR10 LR5 ; SET LR11 LR15 ;;
    {{ mac(true, true) }} ; {{ next_coeff() }} ;;
    {{ mac(true) }} ;;
channel:
    LD.MULT R0 LR10 {{ spatial }} ;;
    {{ next_coeff() }} ; ADD LR10 LR10 {{ cr.in0_d2 }} ;;
    {{ mac() }} ; {{ next_coeff() }} ;;
    {{ mac() }} ; DEC LR11 1 ; BNE LR11 CR1 channel ;;
    ACTIVATE.QUANTIZE generic {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR8 1 ; DEC LR9 1 ; BNE LR9 CR1 tile ;;
    INC LR5 1 ; DEC LR14 1 ; BNE LR14 CR1 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
