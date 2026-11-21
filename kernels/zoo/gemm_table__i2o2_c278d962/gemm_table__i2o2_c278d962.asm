{% set spatial = m * k > in0_d0 * in0_d1 * in0_d2 %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ;;
{% endmacro %}
{% macro load_vec() -%}
{% if spatial %}
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; ADD LR9 LR9 {{ cr.S }}
{% else %}
    LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1
{% endif %}
{%- endmacro %}
{% macro mac(prefetch) %}
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR10 1 {% if prefetch %}; {{ load_vec() | trim }}{% endif %} ;;
{% endmacro %}
{% macro chunk(count, label) %}
    SET LR10 CR0 ; SET LR11 CR0 ;;
    DEC LR10 1 ;;
{% if spatial %}
    LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ;;
{% else %}
    LD.MULT R0 LR7 {{ cr.in0 }} ; INC LR7 1 ;;
{% endif %}
    {{ load_vec() | trim }} ;;
{% if count > 8 %}
    INC LR11 {{ (count - 1) // 8 }} ;;
{{ label }}:
{% for i in range(8) %}
    {{ mac(true) }}
{% endfor %}
    DEC LR11 1 ;;
    BNE LR11 CR0 {{ label }} ;;
{% endif %}
{% for i in range((count - 1) % 8) %}
    {{ mac(true) }}
{% endfor %}
    {{ mac(false) }}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR12 CR1 ; DEC LR1 1 ;;
{% for i in range(5) %}
    LD.LUT {{ i }} {{ cr.lut }} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
{% if spatial %}
    SET LR4 CR0 ;;
batch:
    SET LR5 CR0 ; SET LR6 CR0 ;;
    DEC LR6 1 ;;
channel:
    SET LR7 CR0 ;;
spatial_row:
    SET LR8 LR6 ; SET LR15 CR0 ;;
    INC LR15 3 ;;
coeff_part:
    ADD LR9 LR3 LR7 ; SET LR14 CR0 ;;
    LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1 ; SUB LR9 LR9 {{ cr.S }} ;;
    SET LR13 CR0 ;;
    INC LR13 3 ;;
    BNE LR15 LR13 bias_add ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; BNE LR12 CR0 bias_done ;;
bias_add:
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
bias_done:
{% else %}
matrix_row:
    SET LR4 CR0 ; SET LR5 CR0 ;;
    DEC LR5 1 ;;
output_block:
    SET LR7 LR3 ; SET LR14 CR0 ;;
    LD.MULT.CYCLIC LR5 {{ cr.coeff }} LR0 ; INC LR5 1 ; DEC LR7 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% endif %}
{% if k > 128 %}
    INC LR14 {{ (k - 1) // 128 }} ;;
full_chunk:
    {{ chunk(128, 'full_group') }}
    DEC LR14 1 ;;
    BNE LR14 CR0 full_chunk ;;
{% endif %}
    {{ chunk((k - 1) % 128 + 1, 'tail_group') }}
{% if spatial %}
    DEC LR15 1 ;;
    BNE LR15 CR0 coeff_part ;;
{% endif %}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.O }} store_full ;;
    {{ store(cr.tail) }}
{% if spatial %}
    SET LR4 CR0 ;;
    BNE LR12 CR0 spatial_next ;;
store_full:
    {{ store(cr.full) }}
spatial_next:
    INC LR7 1 ;;
    BLT.S LR7 {{ cr.S }} spatial_row ;;
    SET LR6 LR8 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.n }} channel ;;
    SUB LR3 LR9 LR7 ; ADD LR13 LR1 CR1 ;;
    ADD LR3 LR3 {{ cr.S }} ;;
    INC LR3 1 ;;
    BLT.S LR13 {{ cr.OR }} batch ;;
{% else %}
    ADD LR3 LR7 CR1 ; ADD LR13 LR1 CR1 ;;
    BLT.S LR13 {{ cr.OR }} matrix_row ;;
    HALT ;;
store_full:
    {{ store(cr.full) }}
    BNE LR12 CR0 output_block ;;
{% endif %}
    HALT ;;
