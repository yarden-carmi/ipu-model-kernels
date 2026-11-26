{% macro load() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro taps(count, repeat='', final=false) %}
{% for j in range(count) %}
{% set dual = j % 4 != (2 if 64 < k < 128 else 1) if k > 16 else j % 2 != 0 %}
{% if dual %}
    {{ mac('LR5') }} ; INC LR5 1 ; {{ load() }} ;;
{% endif %}
    {{ mac('LR5') }}{% if not dual %} ; INC LR5 1{% endif %}{% if not (final and loop.last) %} ; {{ load() }}{% endif %}{% if repeat and loop.last %} ; DEC LR10 1 ; BNE LR10 CR1 {{ repeat }}{% endif %}{% if final and loop.last and n <= 128 %} ; INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; ADD LR3 LR3 {{ cr.chunks }} ; BNE LR3 {{ cr.last_pixel }} pixel{% endif %} ;;
{% endfor %}
{% endmacro %}

    SUB LR2 LR0 CR1 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
pixel:
    SET LR4 CR0 ; SET LR9 {{ cr.blocks }} ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
tile:
    {{ mac('CR1', true) }} ; {{ load() }} ; SET LR6 LR3 ;;
    {{ mac('CR1') }} ; {{ load() }} ; SUB LR5 LR0 CR1 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
{% if k > 128 %}
    SET LR8 {{ cr.preceding }} ;;
chunk:
    SET LR10 {{ cr.three }} ;;
{% endif %}
{% if k > 32 %}
{% if k <= 128 %}
    SET LR10 {{ cr.tail_groups }} ;;
{% endif %}
taps_loop:
    {{ taps(32, repeat='taps_loop') }}
{% endif %}
{% if k > 128 %}
    {{ taps(32) }}
    INC LR6 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; SUB LR5 LR0 CR1 ; DEC LR8 1 ; BNE LR8 CR1 chunk ;;
{% if (k - 1) % 128 >= 32 %}
    SET LR10 {{ cr.tail_groups }} ;;
tail_loop:
    {{ taps(32, repeat='tail_loop') }}
{% endif %}
{% endif %}
    {{ taps((k - 1) % 32 + 1, final=true) }}
{% if n > 128 %}
{% if n % 128 %}
    BNE LR9 CR1 full_store ;;
{% endif %}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; DEC LR9 1 ; BNE LR9 CR1 next_tile ;;
    ADD LR3 LR3 {{ cr.chunks }} ; BNE LR3 {{ cr.last_pixel }} pixel ;;
{% endif %}
    HALT ;;
{% if n > 128 %}
{% if n % 128 %}
full_store:
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; DEC LR9 1 ;;
{% endif %}
next_tile:
    {{ load() }} ; B tile ;;
{% endif %}
