{# Spatial positions occupy lanes; the prefix uses two coefficient digits per tap. #}
{% set short = k <= 16 %}
{% set singles = k // 4 if short else (3 if k <= 32 else 0) %}
{% set paired = k - singles %}
{% set cut = paired if short else (k // 4 if singles else k) %}
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
    {{ mac('LR1') }} ; INC LR1 1{% if loop.last and singles and not block %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if singles and loop.last and not block %} ; SUB LR1 LR0 CR1 ; {% if short %}{{ next_input() }}{% else %}ADD LR6 LR5 LR9 ; {{ input() }}{% endif %}{% elif singles and not short and j == cut - 1 %} ; ADD LR6 LR6 LR14 ; {{ input() }}{% elif not loop.last %} ; {{ next_input() }}{% elif block %} ; {{ coeff('R0') }}{% else %} ; {{ finish() }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
SUB LR1 LR0 CR1 ; SET LR2 LR13
{%- endmacro %}

{% if 16 <= k <= 96 and k % 16 == 0 %}
{% set size = 3 if k == 16 else 2 %}
{% set groups = 5 if k == 16 else [24, k * 3 // 8] | min %}
{% set prefix = k - groups * size %}
{% macro stage(count, last) %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ next_input() }} ; INC LR9 1 ;;
{% for j in range(count - 2) %}
    {{ mac('CR1') }} ; {{ next_input() }} ;;
{% endfor %}
    {{ mac('CR1') }} ; ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.sums }} LR9{% if not last %} ; {{ next_input() }}{% endif %} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ; SET LR13 CR0 ;;
    SET LR4 CR0 ; SET LR15 CR0 ;;
    INC LR13 127 ; INC LR15 255 ; SET LR14 CR0 ;;
    INC LR14 127 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
    SET LR6 LR5 ; SUB LR9 LR0 CR1 ; SET LR1 CR0 ;;
    INC LR1 {{ prefix }} ;;
skip_prefix:
    ADD LR6 LR6 {{ cr.height }} ; DEC LR1 1 ; BNE LR1 CR1 skip_prefix ;;
    {{ input() }} ;;
{% for g in range(groups) %}
    {{ stage(size, loop.last) }}
{% endfor %}
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
    {{ bias_mac('LR14', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR3 ;;
{% if k <= 32 %}
    {{ bias_mac('LR15') }} ; {{ input() }} ; {{ indices() }} ; ADD LR3 LR3 {{ cr.height }} ;;
{% for j in range(prefix) %}
    {{ mac('LR1') }} ; INC LR1 1{% if loop.last %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1 ; {% if loop.last %}ADD LR6 LR6 {{ cr.height }} ; {{ coeff('R1') }}{% else %}{{ next_input() }}{% endif %} ;;
{% endfor %}
    {{ input() }} ; {{ indices() }} ; SUB LR9 LR0 CR1 ;;
{% else %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
{% for b in range((prefix + 31) // 32) %}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} ; SUB LR9 LR0 CR1 ;;
    {{ pairs([32, prefix - 32 * b] | min, true) }}
    ADD LR6 LR6 {{ cr.height }} ;;
{% endfor %}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} ;;
{% endif %}
{% for g in range(groups) %}
{% for j in range(size) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if loop.last %}INC LR9 1 ; INC LR2 1 ; LD.MULT.CYCLIC LR9 {{ cr.sums }} LR0{% else %}{{ next_input() }}{% endif %} ;;
{% endfor %}
    {{ mac('LR2') }} ; {% if loop.last %}{{ finish() }}{% else %}{{ next_input() }}{% endif %} ;;
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; INC LR12 1 ;;
    DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    BEQ LR10 CR0 end ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
{% else %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR13 CR0 ; SET LR15 CR0 ;;
    INC LR13 127 ; INC LR15 255 ;;
{% if singles and not short %}
    SET LR14 {{ cr.height }} ; SET LR9 CR0 ;;
{% for j in range(singles) %}
    ADD LR14 LR14 {{ cr.height }} ;;
{% endfor %}
{% for j in range(cut) %}
    ADD LR9 LR9 {{ cr.height }} ;;
{% endfor %}
{% endif %}
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR3 ;;
{% if k > 32 %}
    {{ bias_mac('LR15') }} ; {{ coeff('R0') }} ; ADD LR3 LR3 {{ cr.height }} ;;
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ input() }} ; SET LR14 {{ cr.full_blocks }} ;;
{% else %}
    {{ bias_mac('LR15') }} ; {{ input() }} ; ADD LR3 LR3 {{ cr.height }} ; {{ indices() }} ;;
{% endif %}
{% if paired > 32 %}
full_block:
    {{ pairs(32, true) }}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 full_block ;;
{% endif %}
    {{ pairs((paired - 1) % 32 + 1) }}
{% for j in range(singles) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if loop.last %}{{ finish() }}{% else %}{{ next_input() }}{% endif %} ;;
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; INC LR12 1 ;;
    DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    BEQ LR10 CR0 end ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
{% endif %}
