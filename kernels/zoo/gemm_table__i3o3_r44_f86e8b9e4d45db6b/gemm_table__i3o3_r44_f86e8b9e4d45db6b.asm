{% set block_size = 32 %}
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
    {{ mac('LR0', 'LR2') }} ; INC LR2 1{% if not loop.last or more %} ; {{ load_input() }}{% endif %}{% if more and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 full_block{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ;;
{% for segment in range(5) %}
    LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
    INC LR4 1 ;;
{% endfor %}
    SET LR5 CR0 ; SET LR11 CR0 ; SET LR12 {{ cr.batches }} ;;
    DEC LR5 1 ;;
batch:
    SET LR9 LR11 ; SET LR10 {{ cr.height }} ;;
stripe:
    SET LR3 LR9 ; SET LR8 {{ cr.n }} ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR5 ; {{ coeff('LR0', true) }} ;;
    {{ mac('LR0', 'CR1', true) }} ; {{ coeff('LR0', true) }} ; SET LR14 {{ cr.full_blocks }} ;;
    {{ mac('LR0', 'CR1') }} ; {{ load_input() }} ;;
{% if k > block_size %}
full_block:
    {{ block(block_size, true) }}
{% endif %}
    {{ block((k - 1) % block_size + 1) }}
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    ADD LR3 LR3 {{ cr.height }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    ADD LR5 LR5 {{ cr.k }} ; INC LR9 1 ; DEC LR10 1 ; BNE LR10 CR1 stripe ;;
    ADD LR11 LR11 LR15 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
