{# LR0: cyclic weight slot and zero shift; LR1: scalar selector in R0.
   LR2: coefficient cursor; LR4: output cursor; LR5: input pixel base.
   LR6/7: remaining pixels/tiles. For grouped taps LR10 selects the sum
   in R1 and LR11 is its step. Wide K uses LR3/LR8 for input chunks. #}
{% macro coeff() -%}
INC LR2 1 ; LD.MULT.CYCLIC LR2 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro chunk(label, limit) %}
    LD.MULT R0 LR3 {{ cr.in0 }} ; SUB LR1 LR0 CR1 ;;
    {{ coeff() }} ;;
{{ label }}:
    {{ mac('LR1') }} ; INC LR1 1 ; {{ coeff() }} ;;
    {{ mac('LR1') }} ; {{ coeff() }} ; BNE LR1 {{ limit }} {{ label }} ;;
{% endmacro %}
{% macro store(ds) -%}
ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
{%- endmacro %}
{% macro grouped(size, count, finish=false) %}
{% for g in range(count) %}
    {{ mac('LR10') }} ; ADD LR10 LR10 LR11 ; {{ coeff() }} ;;
    {{ plain(size, finish and loop.last) }}
{% endfor %}
{% endmacro %}
{% macro plain(count, finish=false) %}
{% for tap in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {{ coeff() }}{% if finish and loop.last %} ; INC LR4 1 ; {{ store(cr.tail_ds if n <= 128 else cr.full_ds) }}{% if n <= 128 %} ; BNE LR6 CR0 pixel{% else %} ; BNE LR7 CR0 tile{% endif %}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro precise(count, finish=false) %}
{% for tap in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {{ coeff() }} ;;
    {{ mac('LR1') }} ; {{ coeff() }}{% if finish and loop.last %} ; INC LR4 1 ; {{ store(cr.tail_ds if n <= 128 else cr.full_ds) }}{% if n <= 128 %} ; BNE LR6 CR0 pixel{% else %} ; BNE LR7 CR0 tile{% endif %}{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 {{ cr.m }} ;;
    SUB LR4 LR0 CR1 ; SET LR9 CR0 ; LD.LUT 0 {{ cr.lut }} LR0 ;;
{% for segment in range(1, 5) %}
    INC LR9 1 ; LD.LUT {{ segment }} {{ cr.lut }} LR9 ;;
{% endfor %}
{% if k <= 128 %}
{% set size = 2 if k < 32 or k == 128 else 3 %}
{% set precise_tail = 8 if k == 32 else 0 %}
{% set grouped_k = k - precise_tail %}
{% set fused = n <= 128 or n % 128 == 0 %}
    SUB LR9 LR0 CR1 ; SET LR11 CR1 ; SET LR12 CR1 ;;
    INC LR11 {{ size - 1 }} ; SET LR8 CR1 ;;
{% if size == 3 %}
    INC LR12 1 ;;
{% endif %}
sum_rows:
    INC LR9 1 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; DEC LR6 1 ;;
    {{ mac('CR1', true) }} ;;
    MULT.RC.VE LR8 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if size == 2 %} ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9 ; BNE LR6 CR0 sum_rows{% endif %} ;;
{% if size == 3 %}
    MULT.RC.VE LR12 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9 ; BNE LR6 CR0 sum_rows ;;
{% endif %}
    SET LR6 {{ cr.m }} ;;
pixel:
    LD.MULT R0 LR5 {{ cr.in0 }} ; SUB LR2 LR0 CR1 ; SET LR7 {{ cr.tiles }}{% if n <= 128 %} ; DEC LR6 1{% endif %} ;;
    LD.MULT R1 LR5 {{ cr.sums }} ;;
    {{ coeff() }} ;;
tile:
    {{ mac('CR1', true) }} ; {{ coeff() }} ; SUB LR1 LR0 CR1 ; SET LR10 {{ cr.scalar_base }} ;;
    {{ mac('CR1') }} ; {{ coeff() }} ; DEC LR7 1{% if n <= 128 %} ; INC LR5 1{% endif %} ;;
{% for block in range((grouped_k // size + 31) // 32) %}
    {{ grouped(size, [32, grouped_k // size - 32 * block] | min, fused and not precise_tail and grouped_k % size == 0 and loop.last) }}
{% endfor %}
    {{ plain(grouped_k % size, fused and not precise_tail) }}
    {{ precise(precise_tail, fused) }}
{% if not fused %}
    BEQ LR7 CR0 last_tile ;;
    INC LR4 1 ; {{ store(cr.full_ds) }} ; B tile ;;
last_tile:
    INC LR4 1 ; {{ store(cr.tail_ds) }} ;;
{% endif %}
{% if n > 128 %}
    INC LR5 1 ; DEC LR6 1 ; BNE LR6 CR1 pixel ;;
{% endif %}
{% else %}
pixel:
    SUB LR2 LR0 CR1 ; SET LR7 {{ cr.tiles }} ;;
tile:
    {{ coeff() }} ; SET LR3 LR5 ; SET LR8 LR13 ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ;;
full_chunk:
    {{ chunk('full_tap', 'LR15') }}
    DEC LR2 1 ; INC LR3 1 ; DEC LR8 1 ; BNE LR8 CR1 full_chunk ;;
    {{ chunk('tail_tap', 'LR14') }}
    DEC LR2 1 ; DEC LR7 1 ; BEQ LR7 CR1 last_tile ;;
    {{ store(cr.full_ds) }} ; INC LR4 1 ; B tile ;;
last_tile:
    {{ store(cr.tail_ds) }} ; INC LR4 1 ; ADD LR5 LR5 {{ cr.chunks }} ; DEC LR6 1 ; BNE LR6 CR1 pixel ;;
{% endif %}
    HALT ;;
