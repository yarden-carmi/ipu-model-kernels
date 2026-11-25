{# R0/R1 hold scalar coefficient digits; the cyclic register holds spatial lanes. #}
{% set wide = k > 64 %}
{% set groups = (3 if k == 32 else 7) if 32 <= k <= 64 else 0 %}
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
{% macro store() -%}
ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
{%- endmacro %}
{% macro finish() -%}
{{ store() }} ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel
{%- endmacro %}
{% macro single(taps) %}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1{% if not loop.last %} ; {{ next_input() }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro pairs(taps, last=false) %}
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not (last and loop.last) %} ; {{ next_input() }}{% elif groups %} ; {{ coeff('R0') }}{% elif not wide %} ; {{ finish() }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro wide_block(taps) %}
    SET LR6 LR9 ; SUB LR1 LR0 CR1 ;;
    {{ input() }} ;;
    {{ single(32 if taps > 32 else taps) }}
{% if taps > 32 %}
    {{ next_input() }} ;;
    {{ single(taps - 32) }}
{% endif %}
    {{ coeff('R0') }} ; SET LR6 LR9 ; SUB LR1 LR0 CR1 ;;
    {{ bias_mac('LR13') }} ; {{ coeff('R1') }} ;;
    {{ bias_mac('LR15') }} ; {{ input() }} ; SET LR2 {{ cr.lane_bias }} ;;
    {{ pairs(32 if taps > 32 else taps, taps <= 32) }}
{% if taps > 32 %}
    {{ pairs(taps - 32, true) }}
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR4 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR15 {{ cr.lane_bias }} ; SET LR13 {{ cr.lane_bias }} ;;
    INC LR15 128 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ; LD.MULT R0 LR0 {{ cr.coeff }} ;;
channel:
{% if wide %}
    {{ bias_mac('LR13', true) }} ; SET LR4 LR3 ; ADD LR3 LR3 {{ cr.height }} ; SET LR9 LR5 ;;
    SET LR14 {{ cr.full_blocks }} ;;
full_block:
    {{ wide_block(64) }}
    DEC LR14 1 ; ADD LR9 LR6 {{ cr.height }} ; {{ coeff('R0') }} ; BEQ LR14 CR1 tail ;;
    {{ bias_mac('LR13') }} ; B full_block ;;
tail:
    {{ wide_block((k - 1) % 64 + 1) }}
    {{ store() }} ; {{ coeff('R0') }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
{% else %}
    {{ bias_mac('LR13', true) }} ; {{ coeff('R1') }} ; SET LR6 LR5 ; SET LR4 LR3 ;;
    {{ bias_mac('LR15') }} ; {{ input() }} ; ADD LR3 LR3 {{ cr.height }} ; SUB LR1 LR0 CR1 ; SET LR2 {{ cr.lane_bias }} ;;
{% set paired = k - 2 * groups %}
{% if paired > 32 %}
    {{ pairs(32) }}
{% endif %}
    {{ pairs((paired - 1) % 32 + 1, true) }}
{% for j in range(groups) %}
    {{ next_input() }} ;;
    {{ mac('LR0') }} ; {{ next_input() }} ;;
    {{ mac('LR13') }} ; {% if loop.last %}{{ finish() }}{% else %}{{ coeff('R0') }}{% endif %} ;;
{% endfor %}
{% endif %}
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
