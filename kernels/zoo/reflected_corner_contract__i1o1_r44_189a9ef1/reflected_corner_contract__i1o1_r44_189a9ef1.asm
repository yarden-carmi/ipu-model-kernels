// One input row per spatial coordinate, with channels in lane order.
{% set w9 = cr.f9 if format == 'fp32' else cr.k9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.k3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.k1 %}
{% macro tap(row, weight, acc, store=false) %}
    LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
    MULT.VE LR0 {{ weight }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ acc }}{% if store %} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7{% endif %} ;;
{% endmacro %}

{% macro pixel() %}
    {{ tap('LR3', w9, 'ACC.ADD.FIRST') }}
    {{ tap('LR5', w3, 'ACC.ADD') }}
    {{ tap('LR4', w3, 'ACC.ADD') }}
    {{ tap('LR6', w1, 'ACC.ADD', true) }}
    INC LR7 1 ;;
{% endmacro %}

{% macro scan(tag) %}
    SET LR3 LR1 ; SET LR4 LR2 ; SET LR9 {{ cr.in0_d3 }} ;;
{{ tag }}_x:
    // Clamp the left and right neighbors within this source row.
    SET LR5 LR3 ; SET LR6 LR4 ; BEQ LR9 {{ cr.in0_d3 }} {{ tag }}_left_ready ;;
    SUB LR5 LR3 CR1 ; SUB LR6 LR4 CR1 ;;
{{ tag }}_left_ready:
    {{ pixel() }}
    SET LR5 LR3 ; SET LR6 LR4 ; BEQ LR9 CR1 {{ tag }}_right_ready ;;
    ADD LR5 LR3 CR1 ; ADD LR6 LR4 CR1 ;;
{{ tag }}_right_ready:
    {{ pixel() }}
    INC LR3 1 ; INC LR4 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 {{ tag }}_x ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    BNE LR12 {{ cr.in0_d2 }} dyadic ;;
    BNE LR13 {{ cr.in0_d3 }} dyadic ;;
identity:
    {{ tap('LR7', 'CR1', 'ACC.ADD.FIRST', true) }}
    INC LR7 1 ; DEC LR14 1 ;;
    BNE LR14 CR0 identity ;;
    HALT ;;

dyadic:
    SET LR10 {{ cr.in0_d0 }} ;;
batch:
    SET LR8 {{ cr.in0_d2 }} ;;
source_y:
    SET LR2 LR1 ; BEQ LR8 {{ cr.in0_d2 }} upper_ready ;;
    SUB LR2 LR1 {{ cr.in0_d3 }} ;;
upper_ready:
    {{ scan('upper') }}
    SET LR2 LR1 ; BEQ LR8 CR1 lower_ready ;;
    ADD LR2 LR1 {{ cr.in0_d3 }} ;;
lower_ready:
    {{ scan('lower') }}
    ADD LR1 LR1 {{ cr.in0_d3 }} ; DEC LR8 1 ;;
    BNE LR8 CR0 source_y ;;
    DEC LR10 1 ;;
    BNE LR10 CR0 batch ;;
    HALT ;;
