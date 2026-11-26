{# One vector covers the spatial width; each tap has coarse and residual digits. #}
{% macro load_coeff(reg) -%}
    INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro load_input() -%}
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro bias_mac(src, first=false) -%}
    MULT.EE {{ src }} CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro mac(src) -%}
    MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro tile(taps, last=false) %}
    {{ load_coeff('R1') }} ; SUB LR1 LR0 CR1 ; SET LR2 LR12 ;;
    {{ load_input() }} ;;
{% for j in range(taps) %}
    {{ mac('LR1') }} ; INC LR1 1 ; ADD LR6 LR6 {{ cr.in0_d2 }} ;;
    {{ mac('LR2') }} ; INC LR2 1 {% if not loop.last %}; {{ load_input() }}{% elif last %}; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% endif %} ;;
{% endfor %}
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR4 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.in0_d2 }} ; SET LR3 CR0 ;;
    SET LR15 CR0 ; SET LR12 CR0 ;;
    INC LR15 255 ; INC LR12 127 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR3 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR3 ;;
{% endfor %}
stripe:
    SET LR8 {{ cr.n }} ; SUB LR7 LR0 CR1 ;;
channel:
    {{ load_coeff('R0') }} ; SET LR6 LR5 ; SET LR14 {{ cr.blocks }} ;;
    {{ bias_mac('LR12', true) }} ; {{ load_coeff('R1') }} ;;
    {{ bias_mac('LR15') }} ; {{ load_coeff('R0') }} ;;
{% if k > 16 %}
full_tile:
    {{ tile(16) }}
    {{ load_coeff('R0') }} ; DEC LR14 1 ; BNE LR14 CR1 full_tile ;;
{% endif %}
    {{ tile((k - 1) % 16 + 1, true) }}
    INC LR4 1 ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    INC LR5 1 ; DEC LR10 1 ; DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    BEQ LR10 CR0 end ;;
    ADD LR5 LR5 {{ cr.batch_skip }} ; SET LR11 {{ cr.in0_d2 }} ; B stripe ;;
end:
    HALT ;;
