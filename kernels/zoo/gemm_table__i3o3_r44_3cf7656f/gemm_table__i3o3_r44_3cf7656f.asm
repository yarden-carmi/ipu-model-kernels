{# Duplicate packed input in adjacent cyclic slots so rotations wrap at lane 128. #}
{% macro coefficient() -%}
INC LR2 1 ; LD.MULT R0 LR2 {{ cr.coeff }}
{%- endmacro %}
{% macro product() -%}
MULT.RC.VV LR1 R0 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro identity(first=false) -%}
MULT.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro input_row(last=false) %}
{% if in_pack > 1 %}
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR9 ;;
{% endif %}
    {{ coefficient() }} ; SET LR1 CR0{% if not last %} ; DEC LR8 1{% endif %} ;;
{% if rotations > 32 %}
    SET LR10 {{ cr.rotations }} ;;
rotate{{ '_last' if last else '' }}:
    {{ coefficient() }} ; {{ product() }} ; DEC LR10 1 ;;
    {{ product() }} ; BEQ LR10 CR0 rotated{{ '_last' if last else '' }} ;;
    {{ coefficient() }} ; {{ 'INC' if in_pack > 1 else 'DEC' }} LR1 {{ in0_d3 }} ; B rotate{{ '_last' if last else '' }} ;;
rotated{{ '_last' if last else '' }}:
    {% if last %}INC LR4 1 ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% else %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; BNE LR8 CR0 input_loop{% endif %} ;;
{% else %}
{% for r in range(rotations) %}
    {{ coefficient() }} ; {{ product() }}{% if r %} ; {{ 'INC' if in_pack > 1 else 'DEC' }} LR1 {{ in0_d3 }}{% endif %} ;;
    {{ product() }} ; {% if not loop.last %}{{ coefficient() }}{% elif last %}INC LR4 1 ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% else %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; BNE LR8 CR0 input_loop{% endif %} ;;
{% endfor %}
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.stripes }} ;;
    SET LR1 CR0 ; SET LR9 CR0 ; SUB LR4 LR0 CR1 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR1 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if in_pack == 1 and pack > 1 %}
    INC LR9 192 ;;
    INC LR9 192 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR9 ;;
{% else %}
    INC LR9 128 ; LD.MULT R1 LR0 {{ cr.coeff }} ;;
{% endif %}
stripe:
    SET LR2 CR0 ; SET LR7 {{ cr.groups }} ; DEC LR6 1 ;;
group:
    {{ coefficient() }} ; SET LR3 LR5 ; SET LR8 {{ cr.groups_before_last }} ;;
    {{ coefficient() }} ; {{ identity(true) }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; {{ identity() }} ;;
{% if input_groups > 1 %}
input_loop:
    {{ input_row() }}
{% endif %}
    {{ input_row(true) }}
    DEC LR7 1 ; BNE LR7 CR1 group ;;
    ADD LR5 LR5 {{ cr.input_groups }} ; BNE LR6 CR0 stripe ;;
    HALT ;;
