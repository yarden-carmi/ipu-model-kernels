{% set legacy = m == 1 %}
{% set cr = dict(in0=cr.in0, coeff=cr.coeff, out0=cr.out0, lut=cr.lut, qf_in0=cr.qf_in0, qf_out0=cr.qf_out0, blocks=cr.blocks if legacy else cr.r8, input_rows=cr.r11 if legacy else cr.r9, active=cr.r8 if legacy else cr.r11, chunks=cr.r12 if legacy else cr.r10, tail_ds=cr.r9 if legacy else cr.r15, tile_coeff=cr.r12, preceding=cr.r10, minus_one=cr.r15, before_last=cr.before_last) %}
{% set split = 24 if k <= 16 else 22 if k <= 32 else 19 if k < 128 else 18 %}
{% set fast = k <= 128 and (n <= 128 or n % 128 == 0) %}
{% set period = k if fast and 32 < k < 128 else 32 %}
{% set phase = period // 2 if fast and 32 < k < 128 else period - 1 %}
{% if fast and 32 < k < 128 %}
{% set split = 37 * k // 64 %}
{% endif %}
{% macro load() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(slot, mode='ADD') -%}
MULT.RC.VE LR0 {{ slot }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro tap(j, last=false, advance=false, residual=none) -%}
{% set extra = residual or (residual is none and ((j + 1) * split + phase) // period != (j * split + phase) // period) %}
{% if extra %}
    {{ mac('LR5') }} ; {{ load() }}{% if advance %} ; INC LR3 1{% endif %} ;;
{% endif %}
    {{ mac('LR5' if last else 'LR7') }}{% if not last %} ; SET LR7 LR5 ; INC LR5 1 ; {{ load() }}{% endif %}{% if advance and not extra %} ; INC LR3 1{% endif %}
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
{% if legacy %}
{% set tail = 1 + (k - 1) % 128 %}
{% set correction = 4 * ((tail // 32) if k < 128 else [1, tail // 4] | min) %}
{% set remainder = tail - 8 * ([0, (tail - correction - 1) // 8] | max) %}
{% set omitted = 1 if 48 <= k < 128 else 3 %}
{% macro scalar_group(label, limit) %}
{{ label }}:
{% for j in range(8) %}
    {{ tap(j, residual=m > 1 and j % 4 != omitted) }}{% if loop.last %} ; BNE LR5 {{ limit }} {{ label }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro legacy_store(ds) -%}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% if k > 128 %}
    INC LR10 127 ;;
{% endif %}
legacy_pixel:
    SET LR4 {{ cr.minus_one }} ; SET LR9 {{ cr.blocks }} ;;
legacy_block:
    {{ load() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load() }} ; SET LR8 {{ cr.preceding }} ;;
{% if m > 1 %}
    {{ mac('CR1') }} ; {{ load() }} ;;
{% endif %}
{% if k > 128 %}
legacy_chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR8 1 ; SET LR5 CR0 ; SET LR7 CR0 ;;
    {{ scalar_group('legacy_full_scalar', 'LR10') }}
    INC LR6 1 ; BNE LR8 CR0 legacy_chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR7 CR0 ;;
{% if tail > remainder %}
    {{ scalar_group('legacy_tail_scalar', cr.before_last) }}
{% endif %}
{% for j in range(remainder - 1) %}
    {{ tap(j, residual=m > 1 and (j % 4 != omitted or j // 4 >= (remainder - correction) // 4)) }} ;;
{% endfor %}
{% set last = remainder - 1 %}
    {{ tap(last, true, residual=m > 1 and (last % 4 != omitted or last // 4 >= (remainder - correction) // 4)) }}{% if n > 128 and n % 128 %} ; BNE LR9 CR0 legacy_full_store {% else %} ; {{ legacy_store(cr.tail_ds) }} ; BNE LR9 CR0 legacy_block {% endif %} ;;
{% if n > 128 and n % 128 %}
    {{ legacy_store(cr.tail_ds) }} ;;
{% endif %}
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BNE LR3 {{ cr.input_rows }} legacy_pixel ;;
{% elif fast %}
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR9 {{ cr.blocks }} ;;
output_tile:
    SET LR4 LR13 ; SET LR3 CR0 ; SUB LR2 LR14 {{ cr.blocks }} ;;
    LD.MULT.CYCLIC LR13 {{ cr.coeff }} LR0 ;;
pixel:
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load() }} ; SET LR5 CR0 ; SET LR7 CR0 ;;
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
{% if legacy and n > 128 and n % 128 %}
legacy_full_store:
    {{ legacy_store(cr.active) }} ; B legacy_block ;;
{% elif not legacy and not fast and n > 128 and n % 128 %}
full_store:
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; B tile ;;
{% endif %}
