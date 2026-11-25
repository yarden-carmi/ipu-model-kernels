{% set w = in0_d3 %}
{% set p = [in0_d2, 128 // w] | min %}
{% set ip = p if in0_d2 % p == 0 else 1 %}
{% set p = 128 // out0_d3 %}
{% set op = p if out0_d1 % p == 0 else 1 %}
{% set transpose = ip != 1 or op != 1 %}
{% set target = cr.spatial if transpose else cr.out0 %}
{% set ds = cr.active ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{# Wider exponent range keeps small values from disappearing when the
   spatial scratch row and its channel-packed destination have different scales. #}
{% set qs = cr.transpose_qf ~ '.L' if transpose and ip < 8 else qo %}
{% macro next_coeff(reg) -%}
    INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro mac(index) -%}
    MULT.RC.VE LR0 {{ index }} 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD
{%- endmacro %}
{% macro input(next=false) -%}
    {% if next %}ADD LR6 LR6 {{ cr.height }} ; {% endif %}LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro taps(count) %}
{# R0/R1 hold the high and low digits for up to 32 taps. Each input
   row is used for both MACs; the second MAC prefetches the next row. #}
{% for j in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; {{ input(true) }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
    SUB LR1 LR0 CR1 ; SET LR2 LR13
{%- endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR4 CR0 ;;
    SET LR13 CR0 ; SET LR10 LR15 ; SET LR11 {{ cr.height }} ;;
    INC LR13 127 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
    SUB LR4 LR0 CR1 ;;
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; {{ next_coeff('R0') }} ; SET LR6 LR5 ;;
    MULT.EE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; {{ next_coeff('R0') }} ;;
    {{ next_coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} ; SET LR14 LR12 ;;
{% if k > 32 %}
block:
    {{ taps(32) }}
    {{ next_coeff('R0') }} ; {{ indices() }} ;;
    {{ next_coeff('R1') }} ;;
    {{ input(true) }} ; DEC LR14 1 ; BNE LR14 CR1 block ;;
{% endif %}
    {{ taps((k - 1) % 32 + 1) }}
    ACTIVATE.QUANTIZE generic {{ ds }} {{ qs }} {{ target }} LR4 ; INC LR4 1 ; {{ next_coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    BEQ LR10 CR0 computed ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 LR3 ; SET LR11 {{ cr.height }} ; B stripe ;;
computed:
{% if transpose %}
{# Each scratch stripe is stored channel-by-channel. Gather one width
   slice per channel into the handed [batch, height, channel-tile] order. #}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR14 LR15 ;;
    SET LR4 CR0 ;;
gather_stripe:
    SET LR8 {{ cr.src_lo }} ; SET LR9 {{ cr.src_hi }} ; SET LR10 CR0 ;;
    INC LR10 {{ ip }} ;;
gather_slice:
    SET LR11 LR5 ; SET LR12 CR0 ;;
    INC LR12 {{ n // op }} ;;
gather_tile:
    SET LR2 {{ cr.src_lo }} ; SET LR3 {{ cr.src_hi }} ; SET LR7 CR0 ;;
    INC LR7 {{ op }} ;;
gather_channel:
    LD.MULT R0 LR11 {{ cr.spatial }} ; SET LR0 LR8 ; SET LR1 LR9 ;;
{% for i in range((w + 7) // 8) %}
    {% if loop.last and w % 8 %}ADDBI LRD0 {{ w % 8 - 8 }} ; ADDBI LRD2 {{ w % 8 - 8 }} ;;{% endif %}
    MULT.VE LR4 CR1 0 LR4 {{ ds }} {{ qs }} ; ACC.RESHAPE LRD0 LRD2 {{ (8 - w % 8) if loop.last and w % 8 else 0 }}{% if loop.last %} ; INC LR11 1{% endif %} ;;
    ADDBI LRD0 8 ; ADDBI LRD2 8 {% if loop.last %}; DEC LR7 1 ; BNE LR7 CR1 gather_channel{% endif %} ;;
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ cr.out_active }}.L {{ qo }} {{ cr.out0 }} LR6 ; DEC LR12 1 ;;
    INC LR6 1 ; BNE LR12 CR0 gather_tile ;;
    ADDBI LRD8 {{ w }} ; DEC LR10 1 ; BNE LR10 CR1 gather_slice ;;
    ADD LR5 LR5 {{ cr.n }} ; DEC LR14 1 ; BNE LR14 CR1 gather_stripe ;;
{% endif %}
    HALT ;;
