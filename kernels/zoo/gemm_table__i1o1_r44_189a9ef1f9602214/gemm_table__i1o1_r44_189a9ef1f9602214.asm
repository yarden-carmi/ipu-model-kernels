{# Broadcast one input channel across the output tile; pipeline coefficient loads. #}
{% macro next_coeff() -%}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, mode='ADD') -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(ds) -%}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro channel(split, advance=true, prefetch=true) -%}
    {% if split %}{{ mac('LR5') }} ; {{ next_coeff() }} ;;{% endif %}
    {% if advance %}{{ mac('LR7') }} ; SET LR7 LR5 ; INC LR5 1{% else %}{{ mac('LR5') }}{% endif %}
    {% if prefetch %}; {{ next_coeff() }}{% endif %}
{%- endmacro %}
{% macro group(period, limit, label) -%}
{{ label }}:
{% for i in range(period) %}
    {{ channel(m > 1) }} {% if loop.last %}; BNE LR5 {{ limit }} {{ label }}{% endif %} ;;
{% endfor %}
{%- endmacro %}
{% set period = 4 if m > 1 else 1 %}
{% set tail = 1 + (k - 1) % 128 %}
{% set remainder = 1 + (tail - 1) % period %}

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
{% if m > 1 %}
    {{ mac('CR1') }} ; {{ next_coeff() }} ;;
{% endif %}
{% if k > 128 %}
full_chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR8 1 ; SET LR5 CR0 ;;
{{ group(period, 'LR10', 'full_scalar') }}
    INC LR6 1 ; BNE LR8 CR0 full_chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ;;
{% if tail > period %}
{{ group(period, cr.before_last, 'tail_scalar') }}
{% endif %}
{% for i in range(remainder - 1) %}
    {{ channel(m > 1) }} ;;
{% endfor %}
{% if n > 128 and n % 128 %}
    {{ channel(m > 1, false, false) }} ; BNE LR9 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ;;
{% else %}
    {{ channel(m > 1, false, false) }} ; {{ store(cr.tail_ds) }} ; BNE LR9 CR0 block ;;
{% endif %}
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BNE LR3 {{ cr.input_rows }} pixel ;;
    HALT ;;
{% if n > 128 and n % 128 %}
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
