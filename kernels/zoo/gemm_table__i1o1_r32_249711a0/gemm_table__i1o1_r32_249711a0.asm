{% macro coeff() -%}
INC LR8 1 ; LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(src, first=false) -%}
MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
    SET LR0 CR0 ; SUB LR8 LR0 CR1 ; SUB LR3 LR0 CR1 ;;
    SET LR11 CR0 ; SET LR6 {{ cr.tiles }} ;;
{% for j in range(5) %}
    {% if j %}INC LR11 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR11 ;;
{% endfor %}
tile:
    SET LR2 CR0 ; SET LR7 {{ cr.k }} ; {{ coeff() }} ;;
    {{ mac('CR1', true) }} ; {{ coeff() }} ;;
    {{ mac('CR1') }} ; LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ coeff() }} ;;
tap:
    {{ mac('LR0') }} ; {{ coeff() }} ;;
    {{ mac('LR0') }} ; ADD LR2 LR2 {{ cr.stride }} ; DEC LR7 1 ; BEQ LR7 CR1 store ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ coeff() }} ; B tap ;;
store:
    DEC LR6 1 ; INC LR3 1 ; BEQ LR6 CR1 last ;;
    ACTIVATE.QUANTIZE generic {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; B tile ;;
last:
    ACTIVATE.QUANTIZE generic {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    HALT ;;
