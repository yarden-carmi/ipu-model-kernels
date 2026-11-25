{% set split = 24 if k <= 16 else 22 if k <= 32 else 19 if k < 128 else 18 %}
{% set fast = k <= 128 and (n <= 128 or n % 128 == 0) %}
{% set period = k if fast and 32 < k < 128 else 32 %}
{% set phase = period - 1 %}
{% if fast and 32 < k < 128 %}
{% set split = 5 * k // 8 - (1 if k > 64 else 0) %}
{% endif %}
{% macro load() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(slot, mode='ADD') -%}
MULT.RC.VE LR0 {{ slot }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro tap(j, last=false, advance=false) -%}
{% if ((j + 1) * split + phase) // period != (j * split + phase) // period %}
    {{ mac('LR5') }} ; {{ load() }}{% if advance %} ; INC LR3 1{% endif %} ;;
{% endif %}
    {{ mac('LR5' if last else 'LR7') }}{% if not last %} ; SET LR7 LR5 ; INC LR5 1 ; {{ load() }}{% endif %}
{%- endmacro %}
{% macro group(label, end) %}
{{ label }}:
{% for j in range(32) %}
    {{ tap(j) }}{% if loop.last %} ; BNE LR5 {{ end }} {{ label }}{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR1 CR0 ; SET LR10 CR0 ; DEC LR2 1 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if fast %}
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR9 {{ cr.blocks }} ;;
output_tile:
    SET LR4 LR13 ; SET LR3 CR0 ; SUB LR2 LR14 {{ cr.blocks }} ;;
    LD.MULT.CYCLIC LR13 {{ cr.coeff }} LR0 ;;
pixel:
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load() }} ; SET LR5 CR0 ;;
    {{ mac('CR1') }} ; {{ load() }} ;;
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% for start in range(0, k - 1, 32) %}
{% for j in range(start, [start + 32, k - 1] | min) %}
    {{ tap(j, false, j == 0) }} ;;
{% endfor %}
{% endfor %}
    {{ tap(k - 1, true, k == 1) }} ; ADD LR2 LR2 {{ cr.blocks }} ; ACTIVATE.QUANTIZE generic {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; SET LR4 LR13 ; LD.MULT.CYCLIC LR13 {{ cr.coeff }} LR0 ; BNE LR3 {{ cr.input_rows }} pixel ;;
    ADD LR13 LR13 {{ cr.tile_coeff }} ; INC LR14 1 ; DEC LR9 1 ; BNE LR9 CR1 output_tile ;;
{% else %}
{% set tail = (k - 1) % 128 + 1 %}
{% set remainder = (tail - 1) % 32 + 1 %}
{% if k > 128 %}
    INC LR10 95 ;;
{% endif %}
    SET LR11 CR0 ; SET LR12 CR0 ;;
    DEC LR12 1 ;;
{% if tail > remainder %}
    INC LR11 {{ tail - remainder - 1 }} ;;
{% endif %}
pixel:
    SET LR4 LR12 ; SET LR9 {{ cr.blocks }} ;;
tile:
    {{ load() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load() }} ; SET LR8 {{ cr.chunks }} ;;
    {{ mac('CR1') }} ; {{ load() }} ; DEC LR8 1 ;;
{% if k > 128 %}
chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ;;
    {{ group('full_group', 'LR10') }}
{% for j in range(32) %}
    {{ tap(j) }} ;;
{% endfor %}
    INC LR6 1 ; DEC LR8 1 ; BNE LR8 CR1 chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ;;
{% if tail > remainder %}
    {{ group('tail_group', 'LR11') }}
{% endif %}
{% for j in range(remainder - 1) %}
    {{ tap(j) }} ;;
{% endfor %}
{% if n > 128 and n % 128 %}
    {{ tap(remainder - 1, true) }} ; BNE LR9 CR0 full_store ;;
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% else %}
    {{ tap(remainder - 1, true) }} ; INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; BNE LR9 CR0 tile ;;
{% endif %}
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BNE LR3 {{ cr.input_rows }} pixel ;;
{% endif %}
    HALT ;;
{% if not fast and n > 128 and n % 128 %}
full_store:
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; B tile ;;
{% endif %}
