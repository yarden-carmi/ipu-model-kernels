{% macro mac(src, acc='ADD') -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ acc }}
{%- endmacro %}
{% macro coeff() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro taps(count, finish=false, group=0) %}
{% for j in range(count) %}
{% set triples = 32 < k < 128 %}
{% set paired = (j % 3 == 0 and j + 2 < count) if triples else (j < 12 and j % 2 == 0 and j + 1 < count) %}
{% if paired %}
    {{ mac('LR11') }} ; INC LR11 1 ; {{ coeff() }} ;;
{% elif not (finish and loop.last) %}
    INC LR11 1 ;
{% endif %}
    {{ mac('LR5') }} ; INC LR5 1 ; {{ coeff() }}{% if finish and loop.last %} ; INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.full if n % 128 == 0 else cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; BNE LR9 CR0 block{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro chunk(count, finish=false) %}
{% if k > 128 %}
    LD.MULT R0 LR6 {{ cr.in0 }} ; SUB LR5 LR12 CR1 ; ADD LR11 LR12 {{ cr.shift }} ;;
    LD.MULT R1 LR6 {{ cr.pairs }} ;;
{% endif %}
{% for g in range((count + 15) // 16) %}
    {{ taps(16 if count - 16*g >= 16 else count - 16*g, finish and loop.last, g) }}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR1 ; SUB LR2 LR0 CR1 ;;
    SET LR3 CR0 ; SET LR12 CR0 ; SET LR6 CR0 ;;
{% for i in range(5) %}
    {% if i %}INC LR6 1 ; {% endif %}LD.LUT {{ i }} {{ cr.lut }} LR6 ;;
{% endfor %}
{% if n <= 64 and k <= 16 %}
    SET LR6 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    INC LR10 64 ; INC LR11 128 ; ADD LR7 LR15 CR1 ; LD.MULT R1 LR7 {{ cr.coeff }} ;;
comp_pixel:
    LD.MULT R0 LR3 {{ cr.in0 }} ; SUB LR4 LR0 CR1 ; SUB LR5 LR12 CR1 ;;
    {{ coeff() }} ;;
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ coeff() }} ;;
{% for j in range(k) %}
    {{ mac('LR5') }} ; INC LR5 1{% if not loop.last %} ; {{ coeff() }}{% else %} ; ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.pairs }} LR6{% endif %} ;;
{% endfor %}
    LD.MULT.CYCLIC LR6 {{ cr.pairs }} LR0 ; INC LR2 1 ; DEC LR14 1 ;;
    MULT.RC.VE LR10 LR11 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; BEQ LR14 CR0 end ;;
    BEQ LR12 CR0 comp_second ;;
    SET LR12 CR0 ; INC LR3 1 ; B comp_pixel ;;
comp_second:
    SET LR12 LR15 ; B comp_pixel ;;
{% else %}
    SUB LR6 LR0 CR1 ; DEC LR8 1 ;;
pair_sum:
    INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    {{ mac('CR1', 'ADD.FIRST') }} ;;
{% if 32 < k < 128 %}
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR7 LR1 CR1 ;;
    MULT.RC.VE LR7 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.pairs }} LR6 ; BNE LR6 LR8 pair_sum ;;
{% else %}
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE identity {{ cr.sum_ds }}.L {{ cr.qf_in0 }}.L {{ cr.pairs }} LR6 ; BNE LR6 LR8 pair_sum ;;
{% endif %}
pixel:
{% if k <= 128 %}
    LD.MULT R0 LR3 {{ cr.in0 }} ; SUB LR4 LR0 CR1 ; SET LR9 {{ cr.blocks }} ;;
    {{ coeff() }} ;;
    LD.MULT R1 LR3 {{ cr.pairs }} ;;
{% else %}
    SUB LR4 LR0 CR1 ; SET LR9 {{ cr.blocks }} ;;
    {{ coeff() }} ;;
{% endif %}
block:
    {{ mac('CR1', 'ADD.FIRST') }} ; {{ coeff() }}{% if k > 128 %} ; SET LR6 LR3{% else %} ; SUB LR5 LR12 CR1 ; ADD LR11 LR12 {{ cr.shift }}{% endif %} ;;
    {{ mac('CR1') }} ; {{ coeff() }}{% if k > 128 %} ; SET LR10 {{ cr.preceding }}{% else %} ; DEC LR9 1{% endif %} ;;
{% if k > 128 %}
full_chunk:
    {{ chunk(128) }}
    INC LR6 1 ; DEC LR10 1 ; BNE LR10 CR1 full_chunk ;;
{% endif %}
{% set fused = k <= 128 and (n <= 128 or n % 128 == 0) %}
    {{ chunk((k - 1) % 128 + 1, fused) }}
{% if not fused %}
{% if n % 128 and n > 128 %}
    BEQ LR9 {% if k > 128 %}CR1{% else %}CR0{% endif %} tail ;;
{% endif %}
{% if n >= 128 and (n % 128 == 0 or n > 128) %}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; {% if k > 128 %}DEC LR9 1 ; BNE LR9 CR1 block{% else %}BNE LR9 CR0 block{% endif %} ;;
{% if n % 128 %}
tail:
{% endif %}
{% endif %}
{% if n % 128 %}
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
{% endif %}
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
{% endif %}
end:
    HALT ;;
