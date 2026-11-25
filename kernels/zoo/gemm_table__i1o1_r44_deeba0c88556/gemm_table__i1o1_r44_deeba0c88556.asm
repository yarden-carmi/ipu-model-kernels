{# Stream coefficient rows one instruction ahead of the MAC. #}
{% macro next_coeff() -%}
    INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, mode='ADD') -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro store(ds) -%}
    INC LR2 1 ; ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro tap(last=false) -%}
    {{ mac('LR5') }} ; {{ next_coeff() }} ;;
    {{ mac('LR5' if last else 'LR7') }}{% if not last %} ; SET LR7 LR5 ; INC LR5 1 ; {{ next_coeff() }}{% endif %}
{%- endmacro %}
{% macro group(label, limit) -%}
{{ label }}:
{% for j in range(8) %}
    {{ tap() }}{% if loop.last %} ; BNE LR5 {{ limit }} {{ label }}{% endif %} ;;
{% endfor %}
{%- endmacro %}
{% set tail = 1 + (k - 1) % 128 %}
{% set remainder = 1 + (tail - 1) % 8 %}
{% set packed = in0_d1 <= 64 %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR1 CR0 ; SET LR10 CR0 ; DEC LR2 1 ;;
    SET LR11 CR0 ; SET LR13 CR0 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if k > 128 %}
    INC LR10 127 ;;
{% endif %}
pixel:
    SET LR4 {{ cr.minus_one }} ; SET LR9 {{ cr.blocks }} ; ADD LR14 LR11 {{ cr.before_last }} ;;
block:
    {{ next_coeff() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ next_coeff() }} ; SET LR8 {{ cr.preceding }} ;;
    {{ mac('CR1') }} ; {{ next_coeff() }} ;;
{% if k > 128 %}
full_chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR8 1 ; SET LR5 CR0 ; SET LR7 CR0 ;;
{{ group('full_scalar', 'LR10') }}
    INC LR6 1 ; BNE LR8 CR0 full_chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 LR11 ; SET LR7 LR11 ;;
{% if tail > remainder %}
{{ group('tail_scalar', 'LR14') }}
{% endif %}
{% for j in range(remainder - 1) %}
    {{ tap() }} ;;
{% endfor %}
{% if n > 128 and n % 128 %}
    {{ tap(true) }} ; BNE LR9 CR0 full_store ;;
    {{ store(cr.tail_ds) }} ;;
{% else %}
    {{ tap(true) }} ; {{ store(cr.tail_ds) }} ; BNE LR9 CR0 block ;;
{% endif %}
    INC LR13 1 ;;
    BEQ LR13 {{ cr.m }} done ;;
{% if packed %}
    BEQ LR11 CR0 second_pixel ;;
    SET LR11 CR0 ;;
{% endif %}
    SET LR3 LR6 ;;
    INC LR3 1 ; B pixel ;;
{% if packed %}
second_pixel:
    SET LR11 {{ cr.in0_d1 }} ; B pixel ;;
{% endif %}
done:
    HALT ;;
{% if n > 128 and n % 128 %}
full_store:
    {{ store(cr.full_ds) }} ; B block ;;
{% endif %}
