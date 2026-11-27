{# Both tensors run channel-first within a spatial stripe. #}
{% macro load_coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro load_input() -%}
INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro mac(index, slot='LR0') -%}
MULT.RC.VE {{ slot }} {{ index }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro taps(count, final) %}
    {{ load_coeff('R0') }} ; SUB LR1 LR0 CR1 ; SET LR2 LR13 ;;
    {{ load_coeff('R1') }} ;;
{% for tap in range(count) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last or not final %} ; {{ load_input() }}{% else %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3{% endif %} ;;
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR13 CR0 ; SET LR3 CR0 ;;
    INC LR13 127 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
{% if k <= 16 %}    SUB LR3 LR0 CR1 ;;{% endif %}
{% if k == 16 %}
    SET LR11 CR0 ; SET LR12 CR0 ;;
    INC LR11 128 ; INC LR12 128 ;;
    INC LR12 128 ;;
{% endif %}
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
{% if k <= 16 %}
{% set sizes = [2,2,3,3,3,3] if k == 16 else [3] * (k // 3) + ([k % 3] if k % 3 else []) %}
    SET LR6 LR5 ; SET LR9 CR0 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% for count in sizes %}
{% set last_group = loop.last %}
{% for tap in range(count) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if loop.first %}.FIRST{% endif %}
    {%- if loop.last %} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9{% endif %}
    {%- if not loop.last or not last_group %} ; {{ load_input() }}{% endif %} ;;
{% endfor %}
{% if not loop.last %}    INC LR9 1 ;;{% endif %}
{% endfor %}
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
{% if k == 16 %}
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR11 ;;
    ADD LR6 LR5 CR1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR12 ;;
{% endif %}
{% else %}
    SET LR8 {{ cr.n }} ; SUB LR7 LR0 CR1 ;;
{% endif %}
channel:
{% if k <= 16 %}
{% if k == 16 %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_coeff('R0') }} ; SET LR1 CR0 ; SET LR9 CR0 ;;
{% else %}
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_coeff('R0') }} ; SUB LR6 LR5 CR1 ; SUB LR1 LR0 CR1 ;;
    {{ load_input() }} ; SET LR2 LR13 ; SUB LR9 LR0 CR1 ;;
    {{ load_coeff('R1') }} ;;
{% endif %}
{% for count in sizes %}
{% set last_group = loop.last %}
{% set resident_head = k == 16 and loop.first %}
{% for tap in range(count) %}
{% if resident_head %}
{% if loop.first %}
    {{ mac('LR0', 'LR11') }} ; {{ load_coeff('R1') }} ; ADD LR6 LR5 CR1 ;;
{% else %}
    {{ mac('LR1', 'LR12') }} ; INC LR1 1 ; SET LR2 LR15 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0 ;;
{% endif %}
{% else %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if loop.last %}INC LR9 1 ; INC LR2 1 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0{% else %}{{ load_input() }}{% endif %} ;;
{% endif %}
{% endfor %}
    {{ mac('LR2') }}{% if last_group %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; {{ load_coeff('R0') }} ; INC LR3 1 ; DEC LR8 1 ; BNE LR8 CR1 channel{% else %} ; {{ load_input() }}{% endif %} ;;
{% endfor %}
{% else %}
    {{ load_coeff('R0') }} ; SUB LR6 LR5 CR1 ; SET LR14 {{ cr.full_blocks }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_coeff('R1') }} ;;
    MULT.EE LR15 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ load_input() }} ;;
{% if k > 32 %}
block:
    {{ taps(32, false) }}
    DEC LR14 1 ; BNE LR14 CR1 block ;;
{% endif %}
    {{ taps((k - 1) % 32 + 1, true) }}
    INC LR3 1 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
{% endif %}
    ADD LR5 LR5 {{ cr.k }} ; DEC LR10 1 ; BNE LR10 CR1 stripe ;;
    HALT ;;
