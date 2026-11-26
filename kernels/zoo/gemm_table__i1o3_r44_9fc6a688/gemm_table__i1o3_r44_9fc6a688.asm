{% set width = out0_d3 %}
{% set pack = 128 // width %}
{% set chunks = (in0_d1 + 127) // 128 %}
{% macro scatter(mask, advance=0) -%}
MULT.EE LR6 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 {{ mask }}{% if advance %} ; ADDBI LRD2 {{ advance }}{% endif %}
{%- endmacro %}
{% macro coeff() -%}
INC LR11 1 ; LD.MULT.CYCLIC LR11 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(bias=false, first=false) -%}
{% if bias %}MULT.RC.VE LR0 CR1{% else %}MULT.RC.VV LR0 R0{% endif %} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SUB LR10 LR0 CR1 ; SET LR5 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ chunks }} ;;
{% for i in range(5) %}
    {% if i %}INC LR5 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR5 ;;
{% endfor %}
stripe:
    SET LR14 LR4 ; SET LR6 CR0 ; SET LR7 {{ cr.k }} ;;
    SUB LR9 LR0 CR1 ;;
tap:
    SET LR8 CR0 ; SET LR2 {{ cr.dest_lo }} ; SET LR3 {{ cr.dest_hi }} ;;
    SUB LR5 LR14 LR15 ; INC LR8 {{ width }} ;;
pixel:
    LD.MULT R0 LR5 {{ cr.in0 }} ; INC LR5 {{ chunks }} ;;
{% for g in range((pack + 7) // 8) %}
    {{ scatter([0, 8 - (pack - g * 8)] | max, 8 * width if not loop.first else 0) }}{% if loop.last %} ; DEC LR8 1{% endif %} ;;
{% endfor %}
    ADDBI LRD2 {{ 1 - 8 * width * ((pack - 1) // 8) }} ; BNE LR8 CR0 pixel ;;
    ACTIVATE.QUANTIZE identity {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L {{ cr.panel }} LR9 ; INC LR9 1 ; DEC LR7 1 ; INC.MODP2 LR6 CR1 7 ;;
    BEQ LR7 CR0 panel_ready ;;
{% if k > 128 %}
    BNE LR6 CR0 tap ;;
    INC LR14 1 ;;
{% endif %}
    B tap ;;
panel_ready:
    SUB LR11 LR0 CR1 ; SET LR12 {{ cr.blocks }} ;;
block:
    {{ coeff() }} ; SUB LR9 LR0 CR1 ; SET LR7 {{ cr.k }} ;;
    {{ mac(true, true) }} ; {{ coeff() }} ;;
    {{ mac(true) }} ; {{ coeff() }} ;;
multiply:
    LD.MULT R0 LR9 {{ cr.panel }} ; INC LR9 1 ;;
    {{ mac() }} ; {{ coeff() }} ;;
    {{ mac() }} ; DEC LR7 1 ; BNE LR7 CR1 next_tap ;;
    BEQ LR12 CR1 tail ;;
    ACTIVATE.QUANTIZE generic {{ cr.full_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ; INC LR10 1 ; DEC LR12 1 ; B block ;;
next_tap:
    {{ coeff() }} ; B multiply ;;
tail:
    ACTIVATE.QUANTIZE generic {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ; INC LR10 1 ; ADD LR4 LR4 {{ cr.stripe_step }} ; DEC LR13 1 ; BNE LR13 CR1 stripe ;;
    HALT ;;
