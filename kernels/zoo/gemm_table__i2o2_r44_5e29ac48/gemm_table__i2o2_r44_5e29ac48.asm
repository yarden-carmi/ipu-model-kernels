{# Each row is one spatial column. Revisit the input taps for the low digits. #}
{% macro coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro input() -%}
LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro mac(src) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro bias_mac(src, first=false) -%}
MULT.EE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro bias_pair(first=false) %}
    {{ coeff('R0') }} ;;
    {{ bias_mac('LR0', first) }} ; {{ coeff('R1') }} ;;
    {{ bias_mac('LR15') }} ;;
{% endmacro %}
{% macro digit_pair(taps, last=false) %}
    {{ coeff('R0') }} ; SET LR6 LR9 ; SUB LR1 LR0 CR1 ;;
    {{ coeff('R1') }} ; SET LR2 {{ cr.lane_bias }} ;;
    {{ input() }} ;;
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; ADD LR6 LR6 {{ cr.width }} ; {{ input() }}{% elif last %} ; ADD LR9 LR6 {{ cr.width }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro block(taps) %}
    {{ digit_pair(taps) }}
    {{ digit_pair(taps, true) }}
{% endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR4 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.width }} ; SET LR15 CR0 ;;
    INC LR15 128 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR0 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR0 ;;
{% endfor %}
    SET LR0 CR0 ;;
stripe:
    SET LR8 {{ cr.n }} ; SET LR7 CR0 ; SET LR3 LR4 ;;
    DEC LR7 1 ;;
channel:
    SET LR9 LR5 ; SET LR12 {{ cr.full_blocks }} ; SET LR14 LR3 ;;
    {{ bias_pair(true) }}
    {{ bias_pair() }}
{% if k > 8 %}
full_block:
    {{ block(8) }}
    DEC LR12 1 ; BNE LR12 CR1 full_block ;;
{% endif %}
    {{ block((k - 1) % 8 + 1) }}
    ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ; ADD LR3 LR3 {{ cr.width }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ;;
    INC LR4 1 ; BEQ LR10 CR0 end ;;
    BNE LR11 CR0 stripe ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; ADD LR4 LR4 {{ cr.output_skip }} ; SET LR11 {{ cr.width }} ; B stripe ;;
end:
    HALT ;;
