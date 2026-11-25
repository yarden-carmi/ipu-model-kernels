{# One vector of spatial positions, with two scalar digits per coefficient. #}
{% macro mac(scalar, first=false) %}
MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro coeff(dest, cyclic=false) %}
INC LR7 1 ; LD.MULT{% if cyclic %}.CYCLIC LR7 {{ cr.coeff }} {{ dest }}{% else %} {{ dest }} LR7 {{ cr.coeff }}{% endif %}
{%- endmacro %}
{% macro next_input() %}ADD LR6 LR6 {{ cr.height }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0{% endmacro %}
{% set wide_precision = k > 64 %}
{% set block_size = 16 if wide_precision else 32 %}
{% macro pair(taps, advance=false, more=false) %}
    {{ coeff('R0') }} ; SET LR1 CR0 ; SET LR2 {{ cr.lanes }} ;;
    {{ coeff('R1') }} ; DEC LR1 1 ; DEC LR2 1 ;;
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if advance or not loop.last %} ; {{ next_input() }}{% endif %}{% if more and loop.last %} ; DEC LR14 1 ; BNE LR14 CR1 full_block{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro block(taps, more=false) %}
{% if wide_precision %}
    SET LR13 LR6 ;;
    {{ pair(taps) }}
    SET LR6 LR13 ; LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR0 ;;
{% endif %}
    {{ pair(taps, more, more) }}
{% endmacro %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.height }} ;;
    SET LR12 CR0 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR12 ;;
    DEC LR7 1 ;;
channel:
    SET LR6 LR5 ; {{ coeff('LR0', true) }} ;;
    {{ mac('CR1', true) }} ; {{ coeff('LR0', true) }} ; SET LR14 {{ cr.full_blocks }} ;;
{% if wide_precision %}
{% for digit in range(2) %}
    {{ mac('CR1') }} ; {{ coeff('LR0', true) }} ;;
{% endfor %}
{% endif %}
    {{ mac('CR1') }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
{% if k > block_size %}
full_block:
    {{ block(block_size, true) }}
{% endif %}
    {{ block((k - 1) % block_size + 1) }}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 == 'silu' else act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    ADD LR3 LR3 {{ cr.height }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR12 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.height }} ; B stripe ;;
end:
    HALT ;;
