{# LR0: cyclic weight slot and zero shift; LR1: scalar selector in R0.
   LR2: coefficient cursor; LR3: input chunk; LR4: output cursor.
   LR5: input pixel base; LR6/7: remaining pixels/tiles; LR8: full chunks. #}
{% macro coeff() -%}
INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro chunk(label, limit) %}
    LD.MULT R0 LR3 {{ cr.in0 }} ; SUB LR1 LR0 CR1 ;;
    {{ coeff() }} ;;
{{ label }}:
    {{ mac('LR1') }} ; INC LR1 1 ; {{ coeff() }} ;;
    {{ mac('LR1') }} ; {{ coeff() }} ; BNE LR1 {{ limit }} {{ label }} ;;
{% endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
{%- endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.m }} ;;
    SUB LR4 LR0 CR1 ; SET LR9 CR0 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR9 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR9 ;;
{% endfor %}
pixel:
    SUB LR2 LR0 CR1 ; SET LR7 {{ cr.tiles }} ;;
tile:
    {{ coeff() }} ; SET LR3 LR5 ; SET LR8 {{ cr.full_chunks }} ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ;;
{% if k > 128 %}
full_chunk:
    {{ chunk('full_tap', cr.full_k) }}
    DEC LR2 1 ; INC LR3 1 ; DEC LR8 1 ; BNE LR8 CR1 full_chunk ;;
{% endif %}
    {{ chunk('tail_tap', cr.last_k) }}
    DEC LR2 1 ; DEC LR7 1 ; BEQ LR7 CR1 last_tile ;;
    {{ store(cr.full_ds) }} ; INC LR4 1 ; B tile ;;
last_tile:
    {{ store(cr.tail_ds) }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.chunks }} ; DEC LR6 1 ; BNE LR6 CR1 pixel ;;
    HALT ;;
