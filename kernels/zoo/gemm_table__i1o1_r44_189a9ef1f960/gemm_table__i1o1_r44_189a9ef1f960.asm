{% set medium = k == 32 and n <= 128 %}
{% set short = k <= 16 and n <= 128 and k % 8 == 0 %}
{% macro load() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro taps(count, repeat='', final=false) %}
{% set paired = 16 < k < 128 and k % 32 == 0 and not medium %}
{% for j in range(count) %}
{% set dual = j % 4 == 0 if medium else (j % 2 != 0 if short else (j % 4 == 3 if k >= 128 or k <= 16 else j % 2 != 0)) %}
{% if medium and j % 4 == 1 %}
    {{ mac('LR7') }} ; {{ load() }} ; INC LR7 4 ;;
{% elif paired %}
{% set dual = j % 2 == 0 %}
{% if dual %}
    {{ mac('LR7') }} ; {{ load() }} ; INC LR7 2 ;;
{% endif %}
{% elif dual %}
    {{ mac('LR5') }} ; INC LR5 1 ; {{ load() }} ;;
{% endif %}
    {{ mac('LR5') }}{% if paired or not dual %} ; INC LR5 1{% endif %}{% if not (final and loop.last) %} ; {{ load() }}{% elif short %} ; LD.MULT.CYCLIC LR15 {{ cr.coeff }} LR0{% endif %}{% if repeat and loop.last %} ; DEC LR10 1 ; BNE LR10 CR1 {{ repeat }}{% endif %}{% if final and loop.last and n <= 128 %} ; INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; ADD LR3 LR3 {{ cr.chunks }} ; BNE LR3 {{ cr.last_pixel }} pixel{% endif %} ;;
{% endfor %}
{% endmacro %}

{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1{% if j == 0 %} ; SUB LR2 LR0 CR1{% if short %} ; INC LR13 128{% elif medium %} ; INC LR13 2 ; INC LR14 125{% endif %}{% endif %}{% if medium and j == 1 %} ; SET LR15 CR1{% endif %} ;;
{% endfor %}
{% if short %}
    LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR13 ;;
    SET LR15 CR1 ; LD.MULT.CYCLIC LR15 {{ cr.coeff }} LR0 ;;
{% elif 16 < k < 128 and k % 32 == 0 and not medium %}
    SET LR13 CR1 ; INC LR14 127 ; DEC LR6 1 ;;
stage:
    {# Stage adjacent sums once per pixel, then reuse them across output tiles. #}
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    {{ mac('CR1', true) }} ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.pairs }} LR6 ; BNE LR6 {{ cr.last_pixel }} stage ;;
{% endif %}
pixel:
{% if medium %}
    {# Forward the three-tap sums through one scratch row. #}
    LD.MULT.CYCLIC LR3 {{ cr.in0 }} LR0 ; SET LR4 CR0 ; SET LR7 LR14 ;;
    {{ mac('CR1', true) }} ; LD.MULT R0 LR3 {{ cr.in0 }} ;;
    MULT.RC.VE LR15 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    MULT.RC.VE LR13 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.pairs }} LR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.pairs }} ; SUB LR5 LR0 CR1 ;;
    {{ mac('CR1', true) }} ; {{ load() }} ;;
{% elif short %}
    {# The bias stays resident; load the pixel while initializing its accumulator. #}
    MULT.RC.VE LR13 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{ cr.in0 }} ; SUB LR5 LR0 CR1 ; SET LR4 CR1 ;;
{% else %}
    SET LR4 CR0 ; SET LR9 {{ cr.blocks }} ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
tile:
    {{ mac('CR1', true) }} ; {{ load() }} ; SET LR6 LR3 ;;
    {{ mac('CR1') }} ; {{ load() }} ; SUB LR5 LR0 CR1{% if 16 < k < 128 and k % 32 == 0 %} ; SUB LR7 LR14 CR1{% endif %} ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
{% if 16 < k < 128 and k % 32 == 0 %}
    LD.MULT R1 LR6 {{ cr.pairs }} ;;
{% endif %}
{% endif %}
{% if k > 128 %}
    SET LR8 LR11 ;;
chunk:
    SET LR10 LR12 ;;
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
