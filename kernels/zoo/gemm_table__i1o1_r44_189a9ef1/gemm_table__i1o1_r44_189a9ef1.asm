{# Stream channel vectors, keeping the pixel's reduction axis resident in Ra. #}
{% macro load_coeff() %}INC LR3 1 ; LD.MULT.CYCLIC LR3 {{ cr.coeff }} LR0{% endmacro %}
{% macro mac(src, acc='ACC.ADD') %}MULT.RC.VE LR0 {{ src }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ acc }}{% endmacro %}
{% macro taps(count, final) %}
{% for j in range(count) %}
    {% set split_tap = j % 4 != 2 if k == 96 else j < split %}
    {% if split_tap %}
    {{ mac('LR4') }} ; INC LR4 1 ; {{ load_coeff() }} ;;
    {% endif %}
    {{ mac('LR4') }} ; {% if not split_tap %}INC LR4 1 ; {% endif %}{{ load_coeff() }} ;
    {% if loop.last and final %}
        INC LR2 1 ; ACTIVATE.QUANTIZE generic {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; BNE LR5 CR0 output_block
    {% elif loop.last %}
        DEC LR7 1 ; BNE LR7 CR1 tap_block
    {% endif %} ;;
{% endfor %}
{% endmacro %}
    DEC LR2 1 ; SET LR6 {{ cr.m }} ; SET LR10 CR0 ;;
{% for segment in range(5) %}
    {% if segment %}INC LR10 1 ; {% endif %}LD.LUT {{ segment }} {{ cr.lut }} LR10 ;;
{% endfor %}
    LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
pixel:
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR3 CR0 ; SET LR5 {{ cr.blocks }} ;;
{% if k > 128 %}
    INC LR1 1 ; LD.MULT R1 LR1 {{ cr.in0 }} ;;
{% endif %}
output_block:
    {{ mac('CR1', 'ACC.ADD.FIRST') }} ; {{ load_coeff() }} ; SUB LR4 LR0 CR1 ; SET LR7 {{ cr.block_count }} ;;
    {{ mac('CR1') }} ; {{ load_coeff() }} ; DEC LR5 1 ;;
{% if k > 16 %}
tap_block:
{{ taps(16, false) }}
{% endif %}
{{ taps((k - 1) % 16 + 1, true) }}
    INC LR1 1 ; DEC LR6 1 ; BNE LR6 CR1 pixel ;;
    HALT ;;
