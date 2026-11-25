{% set w = out0_d3 %}
{% set capacity = 128 // w %}
{% set pack = capacity if n % capacity == 0 else 1 %}
{% set ds = cr.active ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set spatial = cr.repeated if pack > 1 else cr.in0 %}
{% macro copy(skip) %}
    MULT.VE LR4 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 {{ skip }}
{%- endmacro %}
{% macro bias_add(mode) %}
    MULT.RC.VE LR4 CR1 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD{{ mode }}
{%- endmacro %}
{% macro tap() %}
    MULT.RC.VV LR4 R0 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD
{%- endmacro %}

    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
{% if pack > 1 %}
{# Replicate the spatial vector once per input row, then reuse across output tiles. #}
repeat_row:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SET LR7 CR0 ; SET LR2 {{ cr.src_lo }} ; SET LR3 {{ cr.src_hi }} ;;
    MULT.VE LR4 CR0 0 LR4 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR7 {{ pack }} ;;
repeat_slot:
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;
{% for i in range(w // 8) %}
    {{ copy(0) }} ;;
    ADDBI LRD0 8 ; ADDBI LRD2 8 ;;
{% endfor %}
{% if w % 8 %}
    ADDBI LRD0 {{ w % 8 - 8 }} ; ADDBI LRD2 {{ w % 8 - 8 }} ;;
    {{ copy(8 - w % 8) }} ;;
    ADDBI LRD2 8 ;;
{% endif %}
    DEC LR7 1 ; BNE LR7 CR1 repeat_slot ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.repeated }} LR5 ;;
    INC LR5 1 ;;
    BNE LR5 {{ cr.input_rows }} repeat_row ;;
{% endif %}

{% for segment in range(5) %}
    {% if segment %}INC LR6 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR6 ;;
{% endfor %}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 {{ cr.stripes }} ;;
stripe:
    SET LR8 CR0 ; SET LR9 {{ cr.tiles }} ;;
tile:
    LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ; SET LR10 LR5 ; SET LR11 {{ cr.k }} ;;
    {{ bias_add('.FIRST') }} ; INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ;;
    {{ bias_add('') }} ;;
channel:
    LD.MULT R0 LR10 {{ spatial }} ;;
    INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ; INC LR10 1 ;;
    {{ tap() }} ; INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR4 ;;
    {{ tap() }} ; DEC LR11 1 ; BNE LR11 CR1 channel ;;
    ACTIVATE.QUANTIZE generic {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR8 1 ; DEC LR9 1 ; BNE LR9 CR1 tile ;;
    SET LR5 LR10 ; DEC LR7 1 ; BNE LR7 CR1 stripe ;;
    HALT ;;
