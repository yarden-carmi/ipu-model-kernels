{% set ds = cr.active ~ '.L' %}
{% set q = cr.qf_in0 ~ '.L' %}
{% macro route(weight) %}
    MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    MULT.EE LR0 {{ weight }} 0 LR0 {{ ds }} {{ q }} ; ACC.RESHAPE LRD0 LRD4 0 ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ q }} {{ cr.route }} LR12 ;;
    INC LR12 1 ;;
{% endmacro %}

{% macro pixel(tag) %}
    SET LR10 CR0 ; SET LR12 CR1 ; SET LR14 CR0 ;;
{{ tag }}_channel:
    ADD LR11 LR14 LR1 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR12 {{ cr.route }} LR0 ;;
    BEQ LR10 CR0 {{ tag }}_first ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    BNE CR0 CR1 {{ tag }}_after_first ;;
{{ tag }}_first:
    MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
{{ tag }}_after_first:
    INC LR12 1 ;;
    LD.MULT.CYCLIC LR12 {{ cr.route }} LR0 ;;
    MULT.RC.VE LR0 LR6 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    ADD LR11 LR14 LR2 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    MULT.RC.VE LR0 LR3 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    INC LR12 1 ;;
    LD.MULT.CYCLIC LR12 {{ cr.route }} LR0 ;;
    MULT.RC.VE LR0 LR6 0 LR0 {{ ds }} {{ q }} ; ACC.ADD ;;
    INC LR12 1 ; INC LR10 1 ; ADD LR14 LR14 {{ cr.in0_d2 }} ;;
    BNE LR10 LR15 {{ tag }}_channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}

{% macro scan(tag) %}
    SET LR3 CR0 ; SET LR8 {{ cr.in0_d3 }} ;;
{{ tag }}_x:
    SET LR6 LR3 ; BEQ LR8 {{ cr.in0_d3 }} {{ tag }}_left ;;
    DEC LR6 1 ;;
{{ tag }}_left:
    {{ pixel(tag ~ '_even') }}
    SET LR6 LR3 ; BEQ LR8 CR1 {{ tag }}_right ;;
    INC LR6 1 ;;
{{ tag }}_right:
    {{ pixel(tag ~ '_odd') }}
    INC LR3 1 ; DEC LR8 1 ;;
    BNE LR8 CR0 {{ tag }}_x ;;
{% endmacro %}

    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    MULT.EE LR0 CR0 0 LR0 {{ ds }} {{ q }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ ds }} {{ q }} {{ cr.route }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.route }} ; SET LR12 CR1 ;;
make_routes:
    {{ route(cr.f9 if format == 'fp32' else cr.k9) }}
    {{ route(cr.f3 if format == 'fp32' else cr.k3) }}
    {{ route(cr.f1 if format == 'fp32' else cr.k1) }}
    ADDBI LRD4 1 ; INC LR11 1 ;;
    BNE LR11 LR15 make_routes ;;
    SET LR7 CR0 ; SET LR1 CR0 ;;
batch:
    SET LR9 {{ cr.in0_d2 }} ;;
source_y:
    SET LR2 LR1 ; BEQ LR9 {{ cr.in0_d2 }} upper_ready ;;
    DEC LR2 1 ;;
upper_ready:
    {{ scan('upper') }}
    SET LR2 LR1 ; BEQ LR9 CR1 lower_ready ;;
    INC LR2 1 ;;
lower_ready:
    {{ scan('lower') }}
    INC LR1 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 source_y ;;
    DEC LR13 1 ;;
    BNE LR13 CR0 batch ;;
    HALT ;;
