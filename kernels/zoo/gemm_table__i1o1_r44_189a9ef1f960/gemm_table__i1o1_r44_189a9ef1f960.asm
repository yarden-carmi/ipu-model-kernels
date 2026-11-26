{% set shared = k > 32 and k % 2 == 0 %}
{% set splits = 9 if k <= 16 else 24 %}
{% set uniform = n <= 128 or n % 128 == 0 %}
{% macro coeff() -%}
INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false, idx='LR0') -%}
MULT.RC.VE {{ idx }} {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro store(ds) -%}
INC LR3 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3
{%- endmacro %}
{% macro panel(count, final) %}
{% set step = 2 if shared else 1 %}
{% for group in range((count + 31) // 32) %}
{% for j in range(([32, count - 32 * group] | min) // step) %}
    {% if shared %}{{ mac('LR4') }} ; INC LR4 2 ; {{ coeff() }} ;;{% elif j < splits %}{{ mac('LR2') }} ; INC LR2 1 ; {{ coeff() }} ;;{% endif %}
    {% if shared %}{{ mac('LR2') }} ; INC LR2 1 ; {{ coeff() }} ;;{% endif %}
    {{ mac('LR2') }}{% if shared or j >= splits %} ; INC LR2 1{% endif %}
    {%- if not (loop.last and group == (count - 1) // 32) %} ; {{ coeff() }}
    {%- elif not final %} ; INC LR11 1 ; LD.MULT R0 LR11 {{ cr.in0 }}
    {%- elif uniform %} ; {{ store(cr.tail) }} ; DEC LR6 1 ; BNE LR6 CR1 out_tile
    {%- endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SUB LR3 LR0 CR1 ; SET LR13 CR0 ;;
{% for j in range(5) %}
    {% if j %}INC LR10 1 ; {% else %}SET LR10 CR0 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR10 ;;
{% endfor %}
{% if shared %}
    SET LR1 CR1 ; INC LR5 126 ; SUB LR9 LR0 CR1 ;;
stage:
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ;;
    {{ mac('CR1', true) }} ;;
    {{ mac('CR1', false, 'LR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9 ; BNE LR9 LR15 stage ;;
{% endif %}
pixel:
    SET LR6 {{ cr.blocks }} ; SUB LR8 LR0 CR1 ;;
out_tile:
    {{ coeff() }} ; SET LR11 LR13 ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR11 {{ cr.in0 }} ; SET LR7 {{ cr.preceding }} ;;
{% if k > 128 %}
full_panel:
    {% if shared %}LD.MULT R1 LR11 {{ cr.sums }} ; SET LR4 LR5 ;;{% endif %}
    {{ coeff() }} ; SUB LR2 LR0 CR1 ;;
    {{ panel(128, false) }}
    DEC LR7 1 ; BNE LR7 CR1 full_panel ;;
{% endif %}
    {% if shared %}LD.MULT R1 LR11 {{ cr.sums }} ; SET LR4 LR5 ;;{% endif %}
    {{ coeff() }} ; SUB LR2 LR0 CR1 ;;
    {{ panel((k - 1) % 128 + 1, true) }}
{% if not uniform %}
    DEC LR6 1 ; BEQ LR6 CR1 tail_store ;;
    {{ store(cr.full) }} ; B out_tile ;;
tail_store:
    {{ store(cr.tail) }} ;;
{% endif %}
    ADD LR13 LR13 {{ cr.chunks }} ; BNE LR13 {{ cr.last_pixel }} pixel ;;
    HALT ;;
