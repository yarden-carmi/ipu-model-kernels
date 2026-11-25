{# Each vector spans the output height at a fixed batch and column. #}
{% macro mac(scalar, first=false) -%}
MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro coeff(dest, cyclic=false) -%}
INC LR7 1 ; LD.MULT{% if cyclic %}.CYCLIC LR7 {{ cr.coeff }} {{ dest }}{% else %} {{ dest }} LR7 {{ cr.coeff }}{% endif %}
{%- endmacro %}
{% macro load_input() -%}INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{%- endmacro %}
{% macro pair(taps, advance=false) %}
    {{ coeff('R0') }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes }} ;;
    {{ coeff('R1') }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last or advance %} ; {{ load_input() }}{% endif %}{% if advance and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 full_block{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro block(taps, more=false) %}
    SET LR13 LR6 ;;
    {{ pair(taps) }}
    SET LR6 LR13 ; LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR0 ;;
    {{ pair(taps, more) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ;;
{% for segment in range(5) %}
    LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
    INC LR4 1 ;;
{% endfor %}
    SET LR5 CR0 ; SET LR11 CR0 ; SET LR12 {{ cr.batches }} ;;
    DEC LR5 1 ;;
batch:
    SET LR9 LR11 ; SET LR10 {{ cr.width }} ;;
stripe:
    SET LR3 LR9 ; SET LR8 {{ cr.n }} ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR5 ; {{ coeff('LR0', true) }} ;;
    {{ mac('CR1', true) }} ; {{ coeff('LR0', true) }} ; SET LR14 {{ cr.full_blocks }} ;;
{% for i in range(2) %}
    {{ mac('CR1') }} ; {{ coeff('LR0', true) }} ;;
{% endfor %}
    {{ mac('CR1') }} ; {{ load_input() }} ;;
{% if k > 16 %}
full_block:
    {{ block(16, true) }}
{% endif %}
    {{ block((k - 1) % 16 + 1) }}
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    ADD LR3 LR3 {{ cr.width }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    ADD LR5 LR5 {{ cr.k }} ; INC LR9 1 ; DEC LR10 1 ; BNE LR10 CR1 stripe ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
