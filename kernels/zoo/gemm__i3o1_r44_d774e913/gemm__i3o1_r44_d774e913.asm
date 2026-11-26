{# Accumulate two pixels into disjoint feature bands when the output packs two. #}
{% macro mac(scalar, first=false, prefetch=true, extra='') %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% if prefetch %} ; LD.MULT.CYCLIC LR7 {{ cr.coeff }} LR0 ; INC LR7 1{% endif %} {{ extra }} ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR12 CR0 ;;
    SUB LR3 LR0 CR1 ;;
batch:
    SET LR2 LR12 ; SET LR9 {{ cr.pitch }} ;;
panel:
    SET LR1 CR0 ;;
pixel_group:
    SET LR7 CR0 ; SUB LR5 LR2 {{ cr.pitch }} ; SET LR10 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 {% if op == 2 %}; ADD LR4 LR1 CR1{% endif %} ;;
    {{ mac('CR1', true) }}
    {{ mac('CR1') }}
channel:
    LD.MULT R0 LR5 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.pitch }} ; DEC LR10 1 ;;
    {{ mac('LR1') }}
{% if op == 2 %}
    {{ mac('LR1') }}
    {{ mac('LR4') }}
    BEQ LR10 CR0 last_channel ;;
    {{ mac('LR4', extra='; B channel') }}
{% else %}
    BEQ LR10 CR0 last_channel ;;
    {{ mac('LR1', extra='; B channel') }}
{% endif %}
last_channel:
    {{ mac('LR4' if op == 2 else 'LR1', prefetch=false) }}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ; INC LR1 {{ op }} ;;
    BLT.S LR1 {{ cr.panel_width }} pixel_group ;;
    INC LR2 1 ; DEC LR9 1 ; BNE LR9 CR1 panel ;;
    ADD LR12 LR12 {{ cr.batch_pitch }} ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
