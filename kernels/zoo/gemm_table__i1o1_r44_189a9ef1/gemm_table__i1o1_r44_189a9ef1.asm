{% set split = 9 if k <= 16 else (24 if k <= 64 else (22 if k <= 128 else 16)) %}
{% set shared = k in [64, 96] %}
{% set uniform = n <= 128 or n % 128 == 0 %}
{% macro coeff() -%}
INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro store(ds) -%}
INC LR3 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{%- endmacro %}
{% macro taps(count, end='') %}
{% for j in range(count) %}
{% if j < split %}
    {{ mac('LR4') }} ; INC LR4 1 ; {{ coeff() }} ;;
{% endif %}
    {{ mac('LR4') }}{% if j >= split %} ; INC LR4 1{% endif %}
    {%- if not (loop.last and end) %} ; {{ coeff() }}
    {%- elif end == 'panel' %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ cr.in0 }}
    {%- elif uniform %} ; {{ store(cr.tail) }}{% if n > 128 %} ; DEC LR6 1 ; BNE LR6 CR1 out_tile{% endif %}
    {%- endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SUB LR3 LR0 CR1 ; SET LR13 CR0 ;;
{% for j in range(5) %}
    {% if j %}INC LR11 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR11 ;;
{% endfor %}
{% if shared %}
    SET LR1 CR1 ; INC LR5 127 ; SUB LR2 LR0 CR1 ;;
stage:
    INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {{ mac('CR1', true) }} ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR2 ; BNE LR2 {{ cr.last_pixel }} stage ;;
{% endif %}
pixel:
    SET LR6 {{ cr.blocks }} ; SUB LR8 LR0 CR1 ;;
out_tile:
    {{ coeff() }} ; SET LR11 LR13 ; SUB LR4 LR0 CR1 ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR11 {{ cr.in0 }}{% if k > 128 %} ; SET LR7 {{ cr.preceding }}{% endif %} ;;
{% if shared %}
    LD.MULT R1 LR11 {{ cr.sums }} ; SET LR4 LR5 ; SUB LR2 LR0 CR1 ;;
    {{ coeff() }} ;;
{% for group in range(k // 32) %}
{% for pair in range(16) %}
    {{ mac('LR4') }} ; INC LR4 1 ; {{ coeff() }} ;;
    {{ mac('LR2') }} ; INC LR2 1 ; {{ coeff() }} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if loop.last and group == k // 32 - 1 %}{% if uniform %} ; {{ store(cr.tail) }} ; DEC LR6 1 ; BNE LR6 CR1 out_tile{% endif %}{% else %} ; INC LR4 1 ; {{ coeff() }}{% endif %} ;;
{% endfor %}
{% endfor %}
{% else %}
{% if k > 128 %}
full_panel:
    {{ coeff() }} ; SUB LR4 LR0 CR1 ;;
{% for q in range(4) %}
    {{ taps(32, 'panel' if loop.last else '') }}
{% endfor %}
    DEC LR7 1 ; BNE LR7 CR1 full_panel ;;
{% endif %}
    {{ coeff() }}{% if k > 128 %} ; SUB LR4 LR0 CR1{% endif %} ;;
{% set tail = (k - 1) % 128 + 1 %}
{% for q in range((tail + 31) // 32) %}
    {{ taps([32, tail - q * 32] | min, 'out' if loop.last else '') }}
{% endfor %}
{% endif %}
{% if not uniform %}
    DEC LR6 1 ; BEQ LR6 CR1 tail_store ;;
    {{ store(cr.full) }} ; B out_tile ;;
tail_store:
    {{ store(cr.tail) }} ;;
{% endif %}
    ADD LR13 LR13 {{ cr.chunks }} ; BNE LR13 {{ cr.last_pixel }} pixel ;;
    HALT ;;
