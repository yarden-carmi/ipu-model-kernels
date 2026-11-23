{% macro mac(vec, scalar, first=false) %}
MULT.RC.VE {{ vec }} {{ scalar }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro coeff(dest, cyclic=false) %}
INC LR7 1 ; LD.MULT{% if cyclic %}.CYCLIC LR7 {{ cr.coeff }} {{ dest }}{% else %} {{ dest }} LR7 {{ cr.coeff }}{% endif %}
{%- endmacro %}
{% macro load_input() %}INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% macro block(taps, more=false) %}
    {{ coeff('R0') }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes }} ;;
    {{ coeff('R1') }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for j in range(taps) %}
    {{ mac('LR0', 'LR1') }} ; INC LR1 1 ;;
    {{ mac('LR0', 'LR2') }} ; INC LR2 1{% if more or not loop.last %} ; {{ load_input() }}{% endif %}{% if more and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 full_block{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
{% for segment in range(5) %}
    LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
    INC LR4 1 ;;
{% endfor %}
    SET LR5 CR0 ; SET LR10 {{ cr.stripes }} ;;
    DEC LR5 1 ;;
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR5 ; {{ coeff('LR0', true) }} ;;
    {{ mac('LR0', 'CR1', true) }} ; {{ coeff('LR0', true) }} ; SET LR14 {{ cr.full_blocks }} ;;
    {{ mac('LR0', 'CR1') }} ; {{ load_input() }} ;;
{% if k > 32 %}
full_block:
    {{ block(32, true) }}
{% endif %}
    {{ block((k - 1) % 32 + 1) }}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    ADD LR5 LR5 {{ cr.k }} ; DEC LR10 1 ; BNE LR10 CR1 stripe ;;
    HALT ;;
