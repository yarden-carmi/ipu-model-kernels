{# Spatial positions occupy lanes; the prefix uses two coefficient digits per tap. #}
{% set singles = k // 4 + (2 if 24 <= k <= 40 else 0) %}
{% set groups = (singles + 11) // 12 %}
{% set paired = k - singles %}
{% set rotate = 24 <= k <= 40 %}
{% set split = 8 %}
{% set first_tail = singles // 2 %}
{% macro coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro input() -%}
LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro next_input() -%}
ADD LR6 LR6 {{ cr.height }} ; {{ input() }}
{%- endmacro %}
{% macro mac(src) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro bias_mac(src, first=false) -%}
MULT.EE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro finish() -%}
ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel
{%- endmacro %}
{% macro pairs(taps, block=false) %}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1{% if loop.last and (groups or block) %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if rotate and j == taps - split - 1 %} ; SET LR6 LR5 ; {{ input() }}{% elif not loop.last %} ; {{ next_input() }}{% elif not block %}{% if 0 < groups <= 8 %} ; SUB LR1 LR0 CR1 ; {{ next_input() }}{% elif not groups %} ; {{ finish() }}{% endif %}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
SUB LR1 LR0 CR1 ; SET LR2 LR13
{%- endmacro %}

{% macro tail(taps, last=false, loaded=false) %}
{% for j in range(taps) %}
    {% if not (loaded and loop.first) %}SUB LR1 LR0 CR1 ; {{ next_input() }} ;;{% endif %}
    {% for tap in range(((singles - 1) % 12 if last and loop.last else 11)) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if rotate and tap == first_tail - 1 %}ADD LR6 LR5 LR9 ; {{ input() }}{% else %}{{ next_input() }}{% endif %} ;;
    {% endfor %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if last and loop.last %}{{ finish() }}{% else %}{{ coeff('R0') }}{% if loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 tail_block{% endif %}{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR13 CR0 ; SET LR15 CR0 ;;
    INC LR13 127 ; INC LR15 255 ;;
{% if rotate %}
    SET LR9 {{ cr.batch_skip }} ;;
{% for j in range(singles - first_tail - 1) %}
    SUB LR9 LR9 {{ cr.height }} ;;
{% endfor %}
{% endif %}
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; {% if rotate %}ADD LR6 LR5 {{ cr.tail_control }}{% else %}SET LR6 LR5{% endif %} ; SET LR4 LR3 ;;
{% if k > 64 %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }}{% if paired > 32 %} ; SET LR14 {{ cr.full_blocks }}{% endif %} ;;
{% else %}
    {{ bias_mac('LR15') }} ; {{ input() }} ; ADD LR3 LR3 {{ cr.height }} ; {{ indices() }} ;;
{% if paired > 32 %}
    SET LR14 {{ cr.full_blocks }} ;;
{% endif %}
{% endif %}
{% if paired > 32 %}
full_block:
    {{ pairs(32, true) }}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 full_block ;;
{% endif %}
    {{ pairs((paired - 1) % 32 + 1) }}
{% if groups %}
{% if groups > 8 %}
    SET LR14 {{ cr.tail_control }} ;;
tail_block:
    {{ tail(1) }}
    {{ tail(1, true) }}
{% else %}
    {{ tail(groups, true, true) }}
{% endif %}
{% endif %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
