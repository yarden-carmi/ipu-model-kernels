{% set stream = n <= 128 and k <= 128 %}
{% set period = 8 if stream else 4 %}
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

    SUB LR2 LR0 CR1 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if stream %}
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
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ load_coeff() }} ; SET LR8 {{ cr.preceding }} ;;
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
