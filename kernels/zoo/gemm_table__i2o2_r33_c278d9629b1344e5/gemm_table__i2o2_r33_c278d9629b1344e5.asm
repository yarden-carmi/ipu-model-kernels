{# Broadcast one input tap across a tile of output channels. #}
{% macro coeff() -%}
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1
{%- endmacro %}
{% macro mac(more) %}
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR3 1 {% if more %}; {{ coeff() }} ; BLT.S LR3 LR7 taps{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
{% endmacro %}
{% macro lut_row(i) %}
    LD.LUT {{ i }} {{ cr.lut }} LR10 ;;
    INC LR10 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR10 CR0 ;;
    SET LR8 CR0 ; SET LR12 {{ cr.rows }} ; DEC LR5 1 ;;
{% for i in range(5) %}
    {{ lut_row(i) }}
{% endfor %}
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ; SET LR1 CR0 ;;
    DEC LR4 1 ; DEC LR1 1 ;;
tile:
    SET LR2 LR8 ; SET LR9 {{ cr.chunks }} ;;
{% if bias %}
    LD.MULT R0 LR1 {{ cr.b }} ; INC LR1 1 ;;
{% endif %}
    MULT.VE LR0 {{ 'CR1' if bias else 'CR0' }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; DEC LR2 1 ; DEC LR6 1 ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; INC LR2 1 ; DEC LR9 1 ; SET LR3 CR0 ;;
    DEC LR3 1 ; SET LR7 {{ cr.full_bound }} ; BNE LR9 CR0 preload ;;
    SET LR7 {{ cr.tail_bound }} ;;
preload:
    {{ coeff() }} ; BLT.S LR7 LR3 last_tap ;;
taps:
    {{ mac(true) }}
last_tap:
    {{ mac(false) }}
    BNE LR9 CR0 chunk ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full_ds) }}
    B tile ;;
last_tile:
    {{ store(cr.tail_ds) }}
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR12 1 ;;
    BNE LR12 CR0 row ;;
    HALT ;;
