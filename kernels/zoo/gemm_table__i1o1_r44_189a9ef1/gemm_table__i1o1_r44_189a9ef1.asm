{% set stream = n <= 128 and k <= 128 %}
{% set period = 2 %}
{% set shared = 16 < k < 128 %}
{% set span = 3 %}
{% set phase = 1 if k > 128 else 0 %}
{% macro mac(src, mode='ADD') -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro load_coeff() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro tap(j, last=false) -%}
{% set src = 'LR7' if j % 2 else 'LR5' %}
{% set next = 'LR5' if j % 2 else 'LR7' %}
{% if j % period != phase %}
    {{ mac(src) }} ; {{ load_coeff() }} ;;
{% endif %}
    {{ mac(src) }} ; INC {{ next }} 2{% if not last %} ; {{ load_coeff() }}{% endif %}
{%- endmacro %}
{% macro groups(label) %}
{{ label }}:
{% for j in range(32) %}
    {{ tap(j) }}{% if loop.last %} ; DEC LR10 1 ; BNE LR10 CR1 {{ label }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro store(ds) -%}
INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro shared_taps() %}
{% for group in range((k + 15) // 16) %}
{% set size = [16, k - group * 16] | min %}
{% for j in range(size) %}
{% set covered = [size, 12] | min if k <= 32 else size %}
{% set prefix = size - (covered // span) * span if k <= 32 else 0 %}
{% set split = j < prefix %}
{% if split %}
    {{ mac('LR5') }} ; INC LR5 1 ; {{ load_coeff() }}{% if j == prefix - 1 and prefix < size %} ; INC LR11 {{ prefix }}{% endif %} ;;
{% elif (j - prefix) % span == 0 and j + span <= size %}
    {{ mac('LR11') }} ; {{ load_coeff() }} ; INC LR11 {{ span }} ;;
{% endif %}
{% set finish = j == size - 1 and group == (k - 1) // 16 %}
    {{ mac('LR5') }}{% if not split %} ; INC LR5 1{% endif %}{% if finish and n <= 128 %} ; SET LR4 CR0 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; {{ store(cr.tail_ds) }} ; BNE LR3 LR14 pixel{% elif finish %} ; BNE LR9 CR0 shared_full{% else %} ; {{ load_coeff() }}{% if k > 32 and j == size - 1 and size % span %} ; INC LR11 {{ size % span }}{% endif %}{% endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

    SUB LR2 LR0 CR1 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if shared %}
{# Precompute sliding three-channel sums once per pixel for all output tiles. #}
    SET LR1 CR1 ; SUB LR6 LR0 CR1 ; SET LR7 CR1 ;;
    INC LR7 1 ;;
sum_rows:
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.RC.VE LR7 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR6 ; BNE LR6 LR14 sum_rows ;;
{% if n <= 128 %}
    SUB LR3 LR0 CR1 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
pixel:
    INC LR3 1 ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
    LD.MULT R1 LR3 {{ cr.sums }} ;;
{% else %}
pixel:
    LD.MULT R0 LR3 {{ cr.in0 }} ; SUB LR4 LR0 CR1 ; SET LR9 {{ cr.blocks }} ;;
    LD.MULT R1 LR3 {{ cr.sums }} ;;
    {{ load_coeff() }} ;;
{% endif %}
shared_tile:
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load_coeff() }} ; SUB LR5 LR0 CR1 ; SET LR11 LR12 ;;
    {{ mac('CR1') }} ; {{ load_coeff() }}{% if n > 128 %} ; DEC LR9 1{% endif %} ;;
    {{ shared_taps() }}
{% if n > 128 %}
    {{ store(cr.tail_ds) }} ; INC LR3 1 ; BNE LR3 LR14 pixel ;;
{% endif %}
    HALT ;;
{% if n > 128 %}
shared_full:
    {{ store(cr.full_ds) }} ; {{ load_coeff() }} ; B shared_tile ;;
{% endif %}
{% elif stream %}
    LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
pixel:
    LD.MULT R0 LR3 {{ cr.in0 }} ; SET LR5 CR0 ; SUB LR7 LR0 CR1 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load_coeff() }} ; INC LR3 1 ;;
    {{ mac('CR1') }} ; {{ load_coeff() }} ; SET LR10 {{ cr.tail_groups }} ;;
{% if k > 32 %}
    {{ groups('stream_groups') }}
{% endif %}
{% for j in range((k - 1) % 32 + 1) %}
    {{ tap(j, loop.last) }}{% if loop.last %} ; SET LR4 CR0 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ; {{ store(cr.tail_ds) }} ; BNE LR3 {{ cr.input_rows }} pixel{% endif %} ;;
{% endfor %}
    HALT ;;
{% else %}
pixel:
    SUB LR4 LR0 CR1 ; SET LR9 {{ cr.blocks }} ;;
tile:
    {{ load_coeff() }} ; SET LR6 LR3 ; DEC LR9 1 ;;
     {{ mac('CR1', 'ADD.FIRST') }} ; {{ load_coeff() }} ; SET LR8 LR13 ;;
    {{ mac('CR1') }} ; {{ load_coeff() }} ;;
{% if k > 128 %}
chunk:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR10 CR1 ; SUB LR7 LR0 CR1 ;;
    INC LR10 3 ;;
    {{ groups('full_groups') }}
    INC LR6 1 ; DEC LR8 1 ; BNE LR8 CR1 chunk ;;
{% endif %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR10 {{ cr.tail_groups }} ; SUB LR7 LR0 CR1 ;;
{% if (k - 1) % 128 >= 32 %}
    {{ groups('tail_groups') }}
{% endif %}
{% for j in range((k - 1) % 32 + 1) %}
    {{ tap(j, loop.last) }}{% if loop.last %}{% if n > 128 and n % 128 %} ; BNE LR9 CR0 full_store{% else %} ; {{ store(cr.tail_ds) }} ; BNE LR9 CR0 tile{% endif %}{% endif %} ;;
{% endfor %}
{% if n > 128 and n % 128 %}
    {{ store(cr.tail_ds) }} ;;
{% endif %}
    ADD LR3 LR3 {{ cr.chunks }} ;;
    BNE LR3 {{ cr.input_rows }} pixel ;;
    HALT ;;
{% if n > 128 and n % 128 %}
full_store:
    {{ store(cr.full_ds) }} ; B tile ;;
{% endif %}
{% endif %}
