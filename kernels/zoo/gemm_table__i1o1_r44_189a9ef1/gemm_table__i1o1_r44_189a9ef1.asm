{# Coefficient rows are streamed one word ahead of the MAC. #}
{% macro next_coeff() -%}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, mode='ADD') -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(ds) -%}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro tap(split, last=false) -%}
    {% if split %}{{ mac('LR5') }} ; {{ next_coeff() }} ;;
    {% endif %}{{ mac('LR5' if last else 'LR7') }}{% if not last %} ; SET LR7 LR5 ; INC LR5 1 ; {{ next_coeff() }}{% endif %}
{%- endmacro %}
{# Omit one residual per complete quartet, retaining all digits in the tail guard. #}
{% set omitted = 1 if k >= 48 and k < 128 else 3 %}
{% macro group(count, label, limit) -%}
{{ label }}:
{% for j in range(count) %}
    {{ tap(m > 1 and j % 4 != omitted) }}{% if loop.last %} ; BNE LR5 {{ limit }} {{ label }}{% endif %} ;;
{% endfor %}
{%- endmacro %}
{% set tail = 1 + (k - 1) % 128 %}
{% set correction = 4 * ((tail // 32) if k < 128 else [1, tail // 4] | min) %}
{% set remainder = tail - 8 * ([0, (tail - correction - 1) // 8] | max) %}
{% set last = remainder - 1 %}
{% set split_last = m > 1 and (last % 4 != omitted or last // 4 >= (remainder - correction) // 4) %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR1 CR0 ; SET LR10 CR0 ; DEC LR2 1 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if k > 128 %}
    INC LR10 127 ;;
{% endif %}
pixel:
    SET LR4 {{ cr.minus_one }} ; SET LR9 {{ cr.blocks }} ;;
block:
    {{ next_coeff() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR8 {{ cr.preceding }} ;;
{% if m > 1 %}
    {{ mac('CR1') }} ; {{ next_coeff() }} ;;
{% endif %}
{% if k > 128 %}
full_chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR8 1 ; SET LR5 CR0 ; SET LR7 CR0 ;;
{{ group(8, 'full_scalar', 'LR10') }}
    INC LR6 1 ; BNE LR8 CR0 full_chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR7 CR0 ;;
{% if tail > remainder %}
{{ group(8, 'tail_scalar', cr.before_last) }}
{% endif %}
{% for start in range(0, remainder - 1, 8) %}
{% for j in range(start, [start + 8, remainder - 1] | min) %}
    {{ tap(m > 1 and (j % 4 != omitted or j // 4 >= remainder // 4 - correction // 4)) }} ;;
{% endfor %}
{% endfor %}
{% if n > 128 and n % 128 %}
    {{ tap(split_last, true) }} ; BNE LR9 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ;;
{% else %}
    {{ tap(split_last, true) }} ; {{ store(cr.tail_ds) }} ; BNE LR9 CR0 block ;;
{% endif %}
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BNE LR3 {{ cr.input_rows }} pixel ;;
    HALT ;;
{% if n > 128 and n % 128 %}
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
