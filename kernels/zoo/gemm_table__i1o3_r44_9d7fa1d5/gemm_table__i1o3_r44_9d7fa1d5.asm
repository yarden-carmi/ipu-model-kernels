{% set paired = in0_d1 <= 64 %}
{% set wide = k > 128 %}
{% set ds = cr.full ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set input_lane = 'LR15' if paired else 'LR0' %}
{% macro reduce(ra) -%}
MULT.RC.VV {{ input_lane }} {{ ra }} 0 LR0 {{ ds }} {{ qi }} ; AGG.SUM LR1 {{ ds }}
{%- endmacro %}
{% macro bias_add(first) -%}
MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; AGG.SUM{% if first %}.FIRST{% endif %} LR1 {{ ds }}
{%- endmacro %}
{% macro dot() -%}
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR9 {{ cr.coeff }} ;;
    {{ reduce('R0') }} ; INC LR9 1 ; LD.MULT R1 LR9 {{ cr.coeff }} ;;
    {{ reduce('R1') }} ; INC LR9 1
{%- endmacro %}
{% macro store(size) -%}
ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'hardswish' else act_out0 }} {{ size }}.L {{ qo }} {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR6 CR0 ; SET LR3 {{ cr.stripes }} ;;
{% for i in range(5) %}
    {% if i %}INC LR0 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR0 ;;
{% endfor %}
    SET LR0 CR0 ;;
stripe:
    SET LR8 CR0 ; SET LR4 {{ cr.n }} ;;
channel:
    SET LR7 LR6 ; SET LR5 {{ cr.out0_d3 }} ; SET LR15 CR0 ;;
pixel:
    SET LR9 LR8 ; SET LR10 LR7{% if wide %} ; SET LR11 {{ cr.chunks }}{% endif %} ;;
    LD.MULT.CYCLIC LR9 {{ cr.coeff }} LR0 ;;
    {{ bias_add(true) }} ; INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.coeff }} LR0 ;;
    {{ bias_add(false) }} ; INC LR9 1 ;;
{% if wide %}
chunk:
    {{ dot() }} ; INC LR10 1 ; DEC LR11 1 ; BNE LR11 CR1 chunk ;;
{% else %}
    {{ dot() }} ;;
{% endif %}
{% if paired %}
    BZ LR15 second_lane ;;
    SET LR15 CR0 ; INC LR7 1 ; B advance ;;
second_lane:
    SET LR15 LR12 ;;
{% else %}
    ADD LR7 LR7 LR13 ;;
{% endif %}
advance:
    INC LR1 1 ; DEC LR5 1 ; BNE LR5 CR1 pixel ;;
    BNE LR1 {{ cr.slot_end }} next_channel ;;
    {{ store(cr.packed) }} ; SET LR1 CR0 ;;
    INC LR2 1 ;;
next_channel:
    SET LR8 LR9 ; DEC LR4 1 ; BNE LR4 CR1 channel ;;
{% if out0_d1 % (128 // out0_d3) %}
    {{ store(cr.tail) }} ; SET LR1 CR0 ;;
    INC LR2 1 ;;
{% endif %}
{% if paired and in0_d3 % 2 %}
    INC LR7 1 ;;
{% endif %}
    SET LR6 LR7 ; DEC LR3 1 ; BNE LR3 CR1 stripe ;;
    HALT ;;
