{% set p = 128 // in0_d3 %}
{% set single = k * 3 // 8 if p == 8 else 0 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.active ~ '.L' %}
{% set input_base = cr.broadcast if p > 1 else cr.in0 %}
{% macro scatter() %}MULT.VE LR15 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 0{% endmacro %}
{% macro load_coeff() %}INC LR7 1 ; LD.MULT R0 LR7 {{ cr.coeff }}{% endmacro %}
{% macro load_input() %}LD.MULT.CYCLIC LR6 {{ input_base }} LR15{% endmacro %}
{% macro mac() %}MULT.RC.VV LR15 R0 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD{% endmacro %}
    SET LR15 CR0 ; SET LR4 CR0 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
{% if p > 1 %}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR9 {{ cr.input_rows }} ;;
{% if in0_d2 % p %}
    SET LR13 CR0 ;;
    INC LR13 {{ (in0_d2 + p - 1) // p }} ;;
{% endif %}
packed_row:
    LD.MULT R0 LR4 {{ cr.in0 }} ; SET LR10 {{ cr.index_lo }} ; SET LR11 {{ cr.index_hi }} ; SET LR8 CR0 ;;
{% if in0_d2 % p %}
    INC LR4 1 ; DEC LR13 1 ; BEQ LR13 CR1 partial_row ;;
    INC LR8 {{ p }} ; B spatial_item ;;
partial_row:
    INC LR8 {{ in0_d2 % p }} ; INC LR13 {{ (in0_d2 + p - 1) // p }} ;;
{% else %}
    INC LR8 {{ p }} ; INC LR4 1 ;;
{% endif %}
spatial_item:
    SET LR2 {{ cr.index_lo }} ; SET LR3 {{ cr.index_hi }} ;;
{% for replica in range(p) %}
    SET LR0 LR10 ; SET LR1 LR11 ;;
{% for block in range(in0_d3 // 8) %}
    {{ scatter() }}{% if not loop.first %} ; ADDBI LRD0 8{% endif %}{% if not loop.first or replica > 0 %} ; ADDBI LRD2 8{% endif %} ;;
{% endfor %}
{% endfor %}
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.broadcast }} LR5 ;;
    INC LR5 1 ; ADDBI LRD10 {{ in0_d3 }} ; DEC LR8 1 ; BNE LR8 CR1 spatial_item ;;
    DEC LR9 1 ; BNE LR9 CR1 packed_row ;;
{% endif %}
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    INC LR12 {{ in0_d0 }} ;;
batch:
    SET LR11 {{ cr.in0_d2 }} ;;
spatial_row:
    SET LR8 {{ cr.groups }} ; SUB LR7 LR15 CR1 ;;
output_group:
    {{ load_coeff() }} ; SET LR6 LR5 ; SET LR9 CR0 ;;
    MULT.VE LR15 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; {{ load_coeff() }} ; INC LR9 {{ k - single }} ;;
{% if single %}
    MULT.VE LR15 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD ; {{ load_coeff() }} ; SET LR10 CR0 ;;
    INC LR10 {{ single }} ;;
single_tap:
    {{ load_input() }} ;;
    {{ mac() }} ; {{ load_coeff() }} ; ADD LR6 LR6 {{ cr.in0_d2 }} ; DEC LR10 1 ; BNE LR10 CR1 single_tap ;;
    {{ load_input() }} ; B coarse_ready ;;
{% else %}
    MULT.VE LR15 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD ; {{ load_input() }} ;;
{% endif %}
tap:
    {{ load_coeff() }} ;;
{% if single %}
coarse_ready:
{% endif %}
    {{ mac() }} ; {{ load_coeff() }} ; ADD LR6 LR6 {{ cr.in0_d2 }} ; DEC LR9 1 ; BEQ LR9 CR1 last_tap ;;
    {{ mac() }} ; {{ load_input() }} ; B tap ;;
last_tap:
    {{ mac() }} ; ACTIVATE.QUANTIZE generic {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; DEC LR8 1 ; BNE LR8 CR1 output_group ;;
    INC LR5 1 ; DEC LR11 1 ; BNE LR11 CR1 spatial_row ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
