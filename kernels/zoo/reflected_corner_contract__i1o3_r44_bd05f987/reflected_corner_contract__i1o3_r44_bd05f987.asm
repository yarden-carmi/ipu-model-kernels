// A weighted one-hot vector routes a source directly into its final lane.
// Generate those vectors in the input format; each has just one magnitude,
// so the scales represent the dyadic coefficients exactly.
{% set q = cr.qf_in0 ~ '.L' %}
{% set ds = cr.pitch_ds ~ '.H' %}
{% set pitch = cr.pitch_ds ~ '.L' %}
{% macro route(weight) %}
    MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.EE LR0 {{ weight }} 0 LR0 {{ ds }} {{ q }} ; ACC.RESHAPE LRD0 LRD4 0 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.route }} LR12 ;;
    INC LR12 1 ;;
{% endmacro %}

{% macro tap(row, delta, odd, acc, advance) %}
    {% if delta == -1 %} SUB LR14 {{ row }} CR1 ;;
    {% elif delta == 1 %} ADD LR14 {{ row }} CR1 ;;
    {% else %} SET LR14 {{ row }} ;;
    {% endif %}
    SUB LR11 LR1 LR10 ;;
    {% if odd %} ADD LR11 LR11 {{ cr.in0_d1 }} ;; {% endif %}
    INC.MODP2 LR11 LR0 9 ; LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR12 {{ cr.route }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ ds }} {{ q }} ; {{ acc }}{% if advance %} ; INC LR12 1{% endif %} ;;
{% endmacro %}

{% macro pixel(tag, odd, other_odd, delta, first=false) %}
    {% if first %}
    BNE LR10 CR0 {{ tag }}_add ;;
    {{ tap('LR8', 0, odd, 'ACC.ADD.FIRST', true) }}
    BNE CR0 CR1 {{ tag }}_rest ;;
{{ tag }}_add:
    {% endif %}
    {{ tap('LR8', 0, odd, 'ACC.ADD', true) }}
    {% if first %} {{ tag }}_rest: {% endif %}
    {{ tap('LR8', delta, other_odd, 'ACC.ADD', false) }}
    {{ tap('LR9', 0, odd, 'ACC.ADD', true) }}
    {{ tap('LR9', delta, other_odd, 'ACC.ADD', true) }}
    INC.MODP2 LR10 CR1 7 ;;
{% endmacro %}

{% macro scan(tag) %}
    SET LR8 LR5 ; SET LR9 LR6 ; SET LR7 {{ pitch }} ;;
{{ tag }}_pair:
    SET LR15 {{ pitch }} ;;
    BEQ LR7 LR15 {{ tag }}_left ;;
    {{ pixel(tag, false, true, -1) }}
    BNE CR0 CR1 {{ tag }}_inner ;;
{{ tag }}_left:
    {{ pixel(tag, false, false, 0, true) }}
{{ tag }}_inner:
    {{ pixel(tag, false, true, 0) }}
    {{ pixel(tag, true, false, 0) }}
    BEQ LR7 CR1 {{ tag }}_right ;;
    {{ pixel(tag, true, false, 1) }}
    BNE CR0 CR1 {{ tag }}_next ;;
{{ tag }}_right:
    {{ pixel(tag, true, true, 0) }}
{{ tag }}_next:
    INC LR8 1 ; INC LR9 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 {{ tag }}_pair ;;
    BNE LR10 CR0 {{ tag }}_done ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; SET LR12 CR1 ;;
    INC LR3 1 ;;
{{ tag }}_done:
{% endmacro %}

    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ q }} {{ cr.route }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.route }} ; SET LR12 CR1 ;;
make_routes:
    {{ route(cr.f9 if format == 'fp32' else cr.k9) }}
    {{ route(cr.f3 if format == 'fp32' else cr.k3) }}
    {{ route(cr.f1 if format == 'fp32' else cr.k1) }}
    ADDBI LRD4 1 ; INC.MODP2 LR10 CR1 7 ;;
    BNE LR10 CR0 make_routes ;;

batch:
    SET LR1 CR0 ;;
channel:
    SET LR5 LR2 ; SET LR4 {{ cr.in0_d2 }} ; SET LR12 CR1 ;;
source_y:
    SET LR6 LR5 ; BEQ LR4 {{ cr.in0_d2 }} upper_ready ;;
    SUB LR6 LR5 {{ pitch }} ;;
upper_ready:
    {{ scan('upper') }}
    SET LR6 LR5 ; BEQ LR4 CR1 lower_ready ;;
    ADD LR6 LR5 {{ pitch }} ;;
lower_ready:
    {{ scan('lower') }}
    ADD LR5 LR5 {{ pitch }} ; DEC LR4 1 ;;
    BNE LR4 CR0 source_y ;;
    INC LR1 1 ;;
    BNE LR1 {{ cr.in0_d1 }} channel ;;
    SET LR2 LR5 ; DEC LR13 1 ;;
    BNE LR13 CR0 batch ;;
    HALT ;;
