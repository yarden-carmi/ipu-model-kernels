{% set wide = k > 128 %}
{% set ip = 128 // in0_d1 if in0_d1 <= 128 else 1 %}
{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% macro reduce(ra) -%}
MULT.RC.VV LR14 {{ ra }} 0 LR0 {{ ds }} {{ qi }} ; AGG.SUM LR1 {{ ds }}
{%- endmacro %}
{% macro bias_add(first) -%}
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR1 {{ ds }}
{%- endmacro %}
{% macro store(size) -%}
ACTIVATE.QUANTIZE generic {{ size }}.L {{ qo }} {{ cr.out0 }} LR2
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR6 CR0 ; SET LR3 {{ cr.stripes }} ; SET LR12 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR12 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR12 ;;
{% endfor %}
stripe:
    SET LR8 CR0 ; SET LR4 {{ cr.n }} ;;
channel:
    SET LR7 LR6 ; SET LR5 {{ cr.out0_d3 }} ; SET LR14 CR0 ;;
pixel:
    SET LR9 LR8 ; SET LR10 LR7 ; {% if wide %}SET LR11 {{ cr.chunks }} ;{% endif %}
    LD.MULT.CYCLIC LR9 {{ cr.coeff }} LR0 ;;
    {{ bias_add(true) }} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.coeff }} LR0 ;;
    {{ bias_add(false) }} ; INC LR9 1 ; LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR9 {{ cr.coeff }} ;;
    {{ reduce('R0') }} ; INC LR9 1 ; LD.MULT R1 LR9 {{ cr.coeff }} ;;
{% if wide %}
    {{ reduce('R1') }} ; INC LR10 1 ; INC LR9 1 ; DEC LR11 1 ;;
chunk:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR9 {{ cr.coeff }} ;;
    {{ reduce('R0') }} ; INC LR9 1 ; LD.MULT R1 LR9 {{ cr.coeff }} ;;
    {{ reduce('R1') }} ; INC LR10 1 ; INC LR9 1 ; DEC LR11 1 ; BNE LR11 CR1 chunk ;;
{% else %}
    {{ reduce('R1') }} ; INC LR9 1 ;;
{% endif %}
    INC LR1 1 ; DEC LR5 1 ;
{% if ip > 1 %}
    INC LR14 {{ k }} ;;
    BNE LR14 LR15 pixel_next ;;
    SET LR14 CR0 ; INC LR7 1 ;;
pixel_next:
{% else %}
    ADD LR7 LR7 LR13 ;;
{% endif %}
    BNE LR5 CR0 pixel ;;
    BNE LR1 {{ cr.slot_end }} next_channel ;;
    {{ store(cr.packed) }} ; SET LR1 CR0 ;;
    INC LR2 1 ;;
next_channel:
    SET LR8 LR9 ; DEC LR4 1 ; BNE LR4 CR1 channel ;;
    SET LR6 LR7 ; DEC LR3 1 ; BNE LR3 CR1 stripe ;;
{% if (out0_d0 * out0_d2 * out0_d1) % (128 // out0_d3) %}
    {{ store(cr.tail) }} ;;
{% endif %}
    HALT ;;
