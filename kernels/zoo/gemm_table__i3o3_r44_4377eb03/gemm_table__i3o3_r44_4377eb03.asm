{# Each accumulator lane is one spatial x; coefficients broadcast over a row. #}
{% macro mac(scalar, first=false) %}
MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro next_coeff(dest, cyclic=false) %}
INC LR7 1 ; LD.MULT{% if cyclic %}.CYCLIC LR7 {{ cr.coeff }} {{ dest }}{% else %} {{ dest }} LR7 {{ cr.coeff }}{% endif %}
{%- endmacro %}

{% macro block(taps, more=false) %}
    SET LR9 LR6 ;;
    {{ next_coeff('R0') }} ; SET LR1 CR0 ; SET LR2 {{ cr.scalar_stride }} ;;
    {{ next_coeff('R1') }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; ADD LR6 LR6 {{ cr.in0_d2 }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% else %} ; SET LR6 LR9 ; LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0{% endif %} ;;
{% endfor %}
    {{ next_coeff('R0') }} ; SET LR1 CR0 ;;
    DEC LR1 1 ;;
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1{% if more or not loop.last %} ; ADD LR6 LR6 {{ cr.in0_d2 }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endif %}{% if more and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 full_block{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR12 {{ cr.in0_d0 }} ;;
{% for segment in range(5) %}
    {% if segment %}INC LR1 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR1 ;;
{% endfor %}
batch:
    SET LR10 {{ cr.in0_d2 }} ;;
stripe:
    SET LR3 LR11 ; SET LR8 {{ cr.n }} ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR5 ; {{ next_coeff('LR0', true) }} ;;
    {{ mac('CR1', true) }} ; {{ next_coeff('LR0', true) }} ; SET LR14 {{ cr.full_blocks }} ;;
    {{ mac('CR1') }} ; {{ next_coeff('LR0', true) }} ;;
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if k > 32 %}
full_block:
    {{ block(32, true) }}
{% endif %}
    {{ block((k - 1) % 32 + 1) }}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 in ['silu', 'hardsigmoid', 'hardswish'] else act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    ADD LR3 LR3 {{ cr.in0_d2 }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    INC LR5 1 ; INC LR11 1 ; DEC LR10 1 ; BNE LR10 CR1 stripe ;;
    ADD LR5 LR5 LR4 ; ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
