{% macro fetch() -%}
INC LR4 1 ; LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0
{%- endmacro %}
{% macro mac(vector, scalar, first=false) -%}
MULT.RC.VE {{ vector }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}
{%- endmacro %}
{% macro taps(count, again='') %}
{% for j in range(count) %}
    {{ fetch() }} ; INC LR5 1 ;;
    {{ mac('LR7', 'LR5') }} ; {{ fetch() }} ;;
    {{ mac('LR7', 'LR5') }}{% if again and loop.last %} ; DEC LR12 1 ; BNE LR12 CR1 {{ again }}{% endif %} ;;
{% endfor %}
{% endmacro %}

    SUB LR2 LR0 CR1 ; SET LR10 {{ cr.lines }} ; LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR15 ;;
{% for j in range(5) %}
    {% if j %}INC LR1 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR1 ;;
{% endfor %}
line:
    SET LR4 CR0 ; SET LR9 {{ cr.tiles }} ;;
tile:
    {{ fetch() }} ; SET LR6 LR3 ;;
    {{ mac('LR0', 'CR1', true) }} ; {{ fetch() }} ; SET LR7 CR0 ;;
    {{ mac('LR0', 'CR1') }} ; SET LR1 LR4 ;;
pixel:
    SET LR4 LR1 ; SET LR8 LR6 ;;
{% if k > 128 %}
    SET LR11 {{ cr.full_chunks }} ;;
chunk:
    SUB LR5 LR0 CR1 ; SET LR12 LR14 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
full_taps:
    {{ taps(8, 'full_taps') }}
    INC LR8 1 ; DEC LR11 1 ; BNE LR11 CR1 chunk ;;
{% endif %}
    SUB LR5 LR0 CR1 ; LD.MULT R0 LR8 {{ cr.in0 }} ;;
{% if (k - 1) % 128 >= 8 %}
    SET LR12 {{ cr.tap_groups }} ;;
tail_taps:
    {{ taps(8, 'tail_taps') }}
{% endif %}
    {{ taps((k - 1) % 8 + 1) }}
    ADD LR6 LR6 {{ cr.chunks }} ; DEC LR7 1 ;;
    BNE LR7 {{ cr.negative_width }} pixel ;;
    INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; DEC LR9 1 ; BNE LR9 CR1 tile ;;
    SET LR3 LR6 ; DEC LR10 1 ; BNE LR10 CR1 line ;;
    HALT ;;
