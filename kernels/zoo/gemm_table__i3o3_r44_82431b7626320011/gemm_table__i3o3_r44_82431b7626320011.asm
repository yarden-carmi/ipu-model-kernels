{# Coefficient digits occupy R0/R1; height rows separate adjacent input channels. #}
{% set singles = 3 if 17 <= k <= 32 else 0 %}
{% set cut = k // 4 %}
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
{% macro pairs(taps, more=false) %}
{# The last coarse MAC can replace R0 while the last residual still uses R1. #}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1{% if singles and loop.last %} ; {{ coeff('R0') }}{% endif %} ;;
    {{ mac('LR2') }} ; INC LR2 1{% if singles and loop.last %} ; SUB LR1 LR0 CR1 ; ADD LR6 LR5 LR9 ; {{ input() }}{% elif singles and j == cut - 1 %} ; ADD LR6 LR6 LR14 ; {{ input() }}{% elif not loop.last %} ; {{ next_input() }}{% elif more %} ; {{ coeff('R0') }}{% else %} ; {{ finish() }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro indices() -%}
SUB LR1 LR0 CR1 ; SET LR2 {{ cr.lane_bias }}
{%- endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR15 {{ cr.lane_bias }} ; SET LR13 {{ cr.lane_bias }} ;;
    INC LR15 128 ;;
{% if singles %}
    SET LR14 {{ cr.height }} ; SET LR9 CR0 ;;
    ADD LR14 LR14 {{ cr.height }} ;;
    ADD LR14 LR14 {{ cr.height }} ;;
    ADD LR14 LR14 {{ cr.height }} ;;
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
{% if k > 32 %}
full_block:
    {{ pairs(32, true) }}
    {{ coeff('R1') }} ; {{ indices() }} ;;
    {{ next_input() }} ; DEC LR14 1 ; BNE LR14 CR1 full_block ;;
{% endif %}
    {{ pairs((k - 1) % 32 + 1 - singles) }}
{% for j in range(singles) %}
    {{ mac('LR1') }} ; INC LR1 1 ; {% if loop.last %}{{ finish() }}{% else %}{{ next_input() }}{% endif %} ;;
{% endfor %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
