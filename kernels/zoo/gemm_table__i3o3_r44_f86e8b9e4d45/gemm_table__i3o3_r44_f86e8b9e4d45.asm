{# Input rows run channel-first within a stripe; output channels stride by height. #}
{% macro load_coeff(reg) -%}
INC LR7 1 ; LD.MULT {{ reg }} LR7 {{ cr.coeff }}
{%- endmacro %}
{% macro load_input() -%}
INC LR6 1 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro mac(index) -%}
MULT.RC.VE LR0 {{ index }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD
{%- endmacro %}
{% macro taps(count, final) %}
    {{ load_coeff('R0') }} ; SUB LR1 LR0 CR1 ; SET LR2 LR13 ;;
    {{ load_coeff('R1') }} ;;
    {{ load_input() }} ;;
{% for tap in range(count) %}
{% if k == 16 and tap >= 12 %}
    {{ mac('LR1') }} ; INC LR1 1 ; INC LR2 1{% if not loop.last %} ; {{ load_input() }}{% elif final %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% endif %} ;;
{% else %}
    {{ mac('LR1') }} ; INC LR1 1 ;;
    {{ mac('LR2') }} ; INC LR2 1{% if not loop.last %} ; {{ load_input() }}{% elif final %} ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4{% endif %} ;;
{% endif %}
{% endfor %}
{% endmacro %}
    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR10 {{ cr.stripes }} ; SET LR11 {{ cr.in0_d2 }} ; SET LR13 CR0 ;;
    INC LR13 127 ; SET LR12 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR4 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR4 ;;
{% endfor %}
stripe:
    SET LR8 {{ cr.n }} ; SUB LR7 LR0 CR1 ; SET LR3 LR12 ;;
channel:
    {{ load_coeff('R0') }} ; SUB LR6 LR5 CR1 ; SET LR14 {{ cr.full_blocks }} ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ load_coeff('R1') }} ;;
    MULT.EE LR15 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR4 LR3 ;;
{% if k > 32 %}
block:
    {{ taps(32, false) }}
    DEC LR14 1 ; BNE LR14 CR1 block ;;
{% endif %}
    {{ taps((k - 1) % 32 + 1, true) }}
    ADD LR3 LR3 {{ cr.out0_d2 }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    ADD LR5 LR5 {{ cr.k }} ; INC LR12 1 ; DEC LR10 1 ;;
    DEC LR11 1 ; BNE LR11 CR1 stripe ;;
    BEQ LR10 CR0 end ;;
    ADD LR12 LR12 {{ cr.output_skip }} ; SET LR11 {{ cr.in0_d2 }} ; B stripe ;;
end:
    HALT ;;
