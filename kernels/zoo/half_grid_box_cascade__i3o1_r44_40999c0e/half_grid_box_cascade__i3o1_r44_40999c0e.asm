{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% set stride = in0_d2 // 4 %}

{# Each output pixel gathers one scalar per channel. Only the named
   accumulator lane is touched; no transpose or quantized scratch is needed. #}
{% macro term(index, weight, first=false) -%}
    MULT.EE {{ index }} {{ weight }} 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR10 {{ cr.one }}.L
{%- endmacro %}

{% macro pixel(tag, copy=false) %}
    SET LR8 LR2 ; SET LR9 LR3 ; SET LR10 CR0 ;;
ch_{{ tag }}:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    {% if copy %}
    {{ term('LR4', 'CR1', true) }} ; INC LR8 {{ stride }} ;;
    {% else %}
    LD.MULT R1 LR9 {{ cr.in0 }} ; {{ term('LR4', w9, true) }} ;;
    {{ term('LR6', w3) }} ; INC LR8 {{ stride }} ; INC LR9 {{ stride }} ;;
    {{ term('LR5', w3) }} ;;
    {{ term('LR7', w1) }} ;;
    {% endif %}
    INC LR10 1 ; BLT.S LR10 LR15 ch_{{ tag }} ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}

{% macro scan(tag) %}
    INC LR12 128 ; SET LR14 CR0 ;;
x_{{ tag }}:
    ADD LR4 LR11 LR14 ; ADD LR5 LR12 LR14 ; BEQ LR14 CR0 left_edge_{{ tag }} ;;
    SUB LR6 LR4 CR1 ; SUB LR7 LR5 CR1 ; BEQ CR0 CR0 left_{{ tag }} ;;
left_edge_{{ tag }}:
    SET LR6 LR4 ; SET LR7 LR5 ;;
left_{{ tag }}:
    {{ pixel(tag ~ '_left') }}
    INC LR14 1 ;;
    BGE.S LR14 {{ cr.in0_d3 }} right_edge_{{ tag }} ;;
    ADD LR6 LR4 CR1 ; ADD LR7 LR5 CR1 ; BEQ CR0 CR0 right_{{ tag }} ;;
right_edge_{{ tag }}:
    SET LR6 LR4 ; SET LR7 LR5 ;;
right_{{ tag }}:
    {{ pixel(tag ~ '_right') }}
    BLT.S LR14 {{ cr.in0_d3 }} x_{{ tag }} ;;
{% endmacro %}

    SET LR1 CR0 ; SET LR2 CR0 ; SET LR11 CR0 ;;
    SET LR13 CR0 ;;
row:
{% if oh == in0_d2 and ow == in0_d3 %}
    SET LR14 CR0 ;;
copy_x:
    ADD LR4 LR11 LR14 ;;
    {{ pixel('copy', true) }}
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.in0_d3 }} copy_x ;;
    INC LR13 1 ;;
{% else %}
    SET LR3 LR2 ; SET LR12 LR11 ; BEQ LR13 CR0 upper_ready ;;
    BNE LR11 CR0 upper_sub ;;
    DEC LR3 1 ; INC LR12 128 ;;
upper_sub:
    SUB LR12 LR12 {{ cr.in0_d3 }} ;;
upper_ready:
    {{ scan('upper') }}

    INC LR13 1 ; SET LR3 LR2 ; SET LR12 LR11 ;;
    BGE.S LR13 {{ cr.in0_d2 }} lower_ready ;;
    INC.MODP2 LR12 {{ cr.in0_d3 }} 7 ;;
    BNE LR12 CR0 lower_ready ;;
    INC LR3 1 ;;
lower_ready:
    {{ scan('lower') }}
{% endif %}
    INC.MODP2 LR11 {{ cr.in0_d3 }} 7 ;;
    BNE LR11 CR0 next_row ;;
    INC LR2 1 ;;
next_row:
    BLT.S LR13 {{ cr.in0_d2 }} row ;;
    HALT ;;
