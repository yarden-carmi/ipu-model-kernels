{% if m == 1 or (in0_d1 <= 64 and k <= 32 and n <= 128) %}
{% macro nc() -%}INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0{%- endmacro %}
{% macro fm(src, mode='ADD') -%}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}{%- endmacro %}
{% macro fs() -%}INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2{%- endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    DEC LR2 1 ; SET LR1 CR0 ; SET LR12 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR1 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR1 ;;
{% endfor %}
{% if m == 1 %}
    SET LR4 CR0 ; SET LR9 {{ cr.blocks }} ;;
    DEC LR4 1 ; SET LR10 CR0 ;;
{% if k > 128 %}    INC LR10 126 ;; {% endif %}
block_f:
    {{ nc() }} ; SET LR6 CR0 ; DEC LR9 1 ;;
    {{ fm('CR1', 'ADD.FIRST') }} ; {{ nc() }} ; SET LR8 {{ cr.preceding }} ;;
{% if k > 128 %}
full_f:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR7 CR0 ; DEC LR8 1 ;;
scalar_f:
    {{ fm('LR7') }} ; SET LR7 LR5 ; INC LR5 1 ; {{ nc() }} ; BNE LR5 LR10 scalar_f ;;
    {{ fm('LR5') }} ; {{ nc() }} ; INC LR6 1 ; BNE LR8 CR0 full_f ;;
{% endif %}
{% set rem = 1 + (k - 1) % 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR5 CR0 ; SET LR7 CR0{% if rem > 1 %} ; SET LR13 {{ cr.shift }}{% endif %} ;;
{% if rem > 1 %}
tail_f:
    {{ fm('LR7') }} ; SET LR7 LR5 ; INC LR5 1 ; {{ nc() }} ; BNE LR5 LR13 tail_f ;;
{% endif %}
{% if n > 128 and n % 128 %}
    {{ fm('LR5') }} ; BNE LR9 CR0 full_store_f ;;
    {{ fs() }} ; HALT ;;
full_store_f:
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; B block_f ;;
{% else %}
    {{ fm('LR5') }} ; {{ fs() }} ; BNE LR9 CR0 block_f ;;
    HALT ;;
{% endif %}
{% else %}
{% macro channel(i, advance=true, prefetch=true) -%}
    {% if i % 16 >= (2 if n < 128 else 0) %}{{ fm('LR5') }} ; {{ nc() }} ;;{% endif %}
    {% if advance %}{{ fm('LR7') }} ; SET LR7 LR5 ; INC LR5 1{% else %}{{ fm('LR5') }}{% endif %}{% if prefetch %} ; {{ nc() }}{% endif %}
{%- endmacro %}
{% macro pixel_f(start, second=false) -%}
    {{ fm('CR1', 'ADD.FIRST') }} ; {{ nc() }} ; SET LR5 {{ start }} ;;
    {{ fm('CR1') }} ; {{ nc() }} ; DEC LR14 1 ;;
{% for i in range(k - 1) %}    {{ channel(i) }} ;; {% endfor %}
    {{ channel(k - 1, false, false) }} ; {{ fs() }} ; SET LR4 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ; {% if second %}INC LR3 1 ; BNE LR14 CR0 packed_f{% else %}BEQ LR14 CR0 finish_f{% endif %} ;;
{%- endmacro %}
    SET LR4 CR0 ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
packed_f:
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
    {{ pixel_f('CR0') }}
    {{ pixel_f('LR15', true) }}
finish_f:
    HALT ;;
{% endif %}
{% else %}
{% set triple = 32 < k < 128 and k != 96 %}
{% macro mac(src, mode='ADD', vector='LR0') -%}
MULT.RC.VE {{ vector }} {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ mode }}
{%- endmacro %}
{% macro coeff() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro store(ds) -%}
INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
{% macro load_input(ptr) %}
    LD.MULT R0 {{ ptr }} {{ cr.in0 }} ; SUB LR5 LR12 CR1 ; ADD LR11 LR12 {{ cr.shift }} ;;
    LD.MULT R1 {{ ptr }} {{ cr.sums }} ;;
{% endmacro %}
{% macro chunk(count, fused=false) %}
{% for g in range((count + 15) // 16) %}
{% set size = [16, count - 16*g] | min %}
{% for j in range(size) %}
{% set extra = j < 5 if k == 96 else j % 3 == 0 and j + 2 < size if triple else j < 12 and j % 2 == 0 and j + 1 < size %}
{% if k <= 16 %}
    {{ mac('LR5') }} ; INC LR5 1 ; {{ coeff() }} ;;
{% elif extra %}
    {{ mac('LR11') }}{% if k != 96 %} ; INC LR11 1{% endif %} ; {{ coeff() }} ;;
{% endif %}
{% set finish = fused and j == size - 1 and g == (count - 1) // 16 %}
    {{ mac('LR5') }}{% if k > 16 %} ; INC LR5 1{% endif %} ; {{ coeff() }}{% if k > 16 and (not extra or k == 96) and not finish %} ; INC LR11 1{% endif %}{% if finish %} ; {{ store('CR8' if n % 128 == 0 else 'CR9') }} ; BNE LR9 CR0 block{% endif %} ;;
{% endfor %}
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR1 ; SET LR6 CR0 ;;
    SUB LR2 LR0 CR1 ; SET LR3 CR0 ; SET LR12 CR0 ;;
{% for j in range(5) %}
    {% if j %}INC LR6 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR6 ;;
{% endfor %}
{% if k > 16 and k != 96 %}
    SUB LR6 LR0 CR1 ; DEC LR8 1 ;;
pair_sum:
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ;;
{% if triple %}
    {{ mac('CR1', vector='LR1') }} ; ADD LR7 LR1 CR1 ;;
{% endif %}
    {{ mac('CR1', vector='LR7' if triple else 'LR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR6 ; BNE LR6 LR8 pair_sum ;;
{% endif %}
pixel:
    SUB LR4 LR0 CR1 ; SET LR9 {{ cr.blocks }} ;;
    {{ coeff() }} ;;
{% if k <= 128 %}
    LD.MULT R0 LR3 {{ cr.in0 }} ;;
{% if k > 16 and k != 96 %}
    LD.MULT R1 LR3 {{ cr.sums }} ;;
{% endif %}
{% endif %}
block:
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ coeff() }}{% if k <= 128 %} ; SUB LR5 LR12 CR1 ; {% if k == 96 %}SET LR11 LR12{% else %}ADD LR11 LR12 {{ cr.shift }}{% endif %}{% else %} ; SET LR6 LR3 ; SET LR10 {{ cr.preceding }}{% endif %} ;;
    {{ mac('CR1') }} ; {{ coeff() }} ; DEC LR9 1 ;;
{% if k > 128 %}
full_chunk:
    {{ load_input('LR6') }}
    {{ chunk(128) }}
    INC LR6 1 ; DEC LR10 1 ; BNE LR10 CR1 full_chunk ;;
    {{ load_input('LR6') }}
{% endif %}
{% set fused = n <= 128 or n % 128 == 0 %}
    {{ chunk((k - 1) % 128 + 1, fused) }}
{% if not fused %}
    BEQ LR9 CR0 tail ;;
    {{ store('CR8') }} ; B block ;;
tail:
    {{ store('CR9') }} ;;
{% endif %}
{% if in0_d1 <= 64 %}
    DEC LR14 1 ; BEQ LR14 CR1 end ;;
    BEQ LR12 CR0 second ;;
    SET LR12 CR0 ; INC LR3 1 ; B pixel ;;
second:
    SET LR12 LR15 ; B pixel ;;
{% else %}
    ADD LR3 LR3 {{ cr.chunks }} ; DEC LR14 1 ; BNE LR14 CR1 pixel ;;
{% endif %}
end:
    HALT ;;
{% endif %}
