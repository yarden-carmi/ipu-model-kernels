{% set p = 128 // out0_d3 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% set input_base = cr.broadcast if p > 1 else cr.in0 %}
{% macro scatter() -%}
MULT.VE LR15 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 0
{%- endmacro %}
{% macro load_coeff() -%}
INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro load_input() -%}
LD.MULT.CYCLIC LR6 {{ input_base }} LR15
{%- endmacro %}
{% macro mac() -%}
MULT.RC.VV LR15 R0 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD
{%- endmacro %}
    SET LR15 CR0 ; SET LR4 CR0 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
{% if p > 1 %}
    SET LR4 CR0 ; SET LR9 {{ cr.input_rows }} ;;
broadcast_row:
    LD.MULT R0 LR4 {{ cr.in0 }} ; SET LR2 {{ cr.index_lo }} ; SET LR3 {{ cr.index_hi }} ;;
{% for replica in range(p) %}
    SET LR0 {{ cr.index_lo }} ; SET LR1 {{ cr.index_hi }} ;;
{% for block in range(out0_d3 // 8) %}
    {{ scatter() }}{% if not loop.first %} ; ADDBI LRD0 8{% endif %}{% if not loop.first or replica > 0 %} ; ADDBI LRD2 8{% endif %} ;;
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.broadcast }} LR4 ;;
    INC LR4 1 ; DEC LR9 1 ; BNE LR9 CR1 broadcast_row ;;
{% endif %}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR11 {{ cr.stripes }} ;;
spatial_row:
    SET LR8 {{ cr.groups }} ; SUB LR7 LR15 CR1 ;;
output_group:
    {{ load_coeff() }} ; SET LR6 LR5 ; SET LR9 {{ cr.k }} ;;
    MULT.VE LR15 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; {{ load_coeff() }} ;;
    MULT.VE LR15 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD ; {{ load_input() }} ;;
tap:
    {{ load_coeff() }} ;;
    {{ mac() }} ; {{ load_coeff() }} ; INC LR6 1 ; DEC LR9 1 ; BEQ LR9 CR1 last_tap ;;
    {{ mac() }} ; {{ load_input() }} ; B tap ;;
last_tap:
    {{ mac() }} ; ACTIVATE.QUANTIZE generic {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; DEC LR8 1 ; BNE LR8 CR1 output_group ;;
    ADD LR5 LR5 {{ cr.k }} ; DEC LR11 1 ; BNE LR11 CR1 spatial_row ;;
    HALT ;;
