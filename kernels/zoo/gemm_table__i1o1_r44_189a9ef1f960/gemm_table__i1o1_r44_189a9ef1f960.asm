{# Each MAC broadcasts one input channel across a tile of output channels. #}
{% macro next_coeff() -%}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, mode='ADD') -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(ds) -%}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro pair(advance, prefetch) -%}
    {{ mac('LR5') }} ; {{ next_coeff() }} ;;
    {{ mac('LR7' if advance else 'LR5') }} {% if advance %}; SET LR7 LR5 ; INC LR5 1 {% endif %}{% if prefetch %}; {{ next_coeff() }} {% endif %}
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR1 CR0 ; SET LR10 CR0 ; DEC LR2 1 ;;
{% for i in range(5) %}
    {% if i %}INC LR1 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if k > 128 %}
    INC LR10 127 ;;
{% endif %}
pixel:
    SET LR4 CR0 ; SET LR9 {{ cr.blocks }} ;;
    DEC LR4 1 ;;
block:
    {{ next_coeff() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR8 {{ cr.preceding }} ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ; SET LR5 CR0 ;;
{% if k > 128 %}
full_chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR8 1 ;;
full_scalar:
    {{ pair(true, true) }} ; BNE LR5 LR10 full_scalar ;;
    INC LR6 1 ; SET LR5 CR0 ; BNE LR8 CR0 full_chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
{% if (k - 1) % 128 %}
tail_scalar:
    {{ pair(true, true) }} ; BNE LR5 {{ cr.before_last }} tail_scalar ;;
{% endif %}
{% if n > 128 and n % 128 %}
    {{ pair(false, false) }} ; BNE LR9 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ;;
{% else %}
    {{ pair(false, false) }} ; {{ store(cr.tail_ds) }} ; BNE LR9 CR0 block ;;
{% endif %}
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BNE LR3 {{ cr.input_rows }} pixel ;;
    HALT ;;
{% if n > 128 and n % 128 %}
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
