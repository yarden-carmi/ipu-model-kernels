{% set w9 = cr.f9 if format == 'fp32' else cr.k9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.k3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.k1 %}
{% macro tap(row, lane, weight) %}
    LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
    MULT.EE {{ lane }} {{ weight }} 0 LR13 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR10 {{ cr.single }}.L ;;
{% endmacro %}
{% macro pixel(lane, other) %}
    {{ tap('LR1', lane, w9) }}
    {{ tap('LR2', other, w3) }}
    {{ tap('LR3', lane, w3) }}
    {{ tap('LR4', other, w1) }}
    INC LR10 1 ;;
{% endmacro %}
{% macro scan(tag, lane, other) %}
    SET LR1 LR11 ; SET LR2 LR12 ; SET LR8 {{ cr.in0_d2 }} ;;
{{ tag }}_y:
    SET LR3 LR1 ; SET LR4 LR2 ; BEQ LR8 {{ cr.in0_d2 }} {{ tag }}_top ;;
    SUB LR3 LR1 {{ cr.pitch }} ; SUB LR4 LR2 {{ cr.pitch }} ;;
{{ tag }}_top:
    {{ pixel(lane, other) }}
    SET LR3 LR1 ; SET LR4 LR2 ; BEQ LR8 CR1 {{ tag }}_bottom ;;
    ADD LR3 LR1 {{ cr.pitch }} ; ADD LR4 LR2 {{ cr.pitch }} ;;
{{ tag }}_bottom:
    {{ pixel(lane, other) }}
    ADD LR1 LR1 {{ cr.pitch }} ; ADD LR2 LR2 {{ cr.pitch }} ; DEC LR8 1 ;;
    BNE LR8 CR0 {{ tag }}_y ;;
{% endmacro %}
{% macro start() %}
    MULT.EE LR13 CR0 0 LR13 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR10 CR0 ;;
{% endmacro %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR7 CR0 ;;
channel:
    ADD LR5 LR14 LR15 ; SET LR11 CR0 ; SET LR9 {{ cr.pitch }} ;;
x_pair:
    {{ start() }}
    SET LR12 LR11 ; SET LR6 LR14 ; BEQ LR9 {{ cr.pitch }} left_ready ;;
    SUB LR12 LR11 CR1 ; SET LR6 LR5 ;;
left_ready:
    {{ scan('a', 'LR14', 'LR6') }}
    SET LR12 LR11 ;;
    {{ scan('b', 'LR14', 'LR5') }}
    {{ store() }}
    {{ start() }}
    SET LR12 LR11 ;;
    {{ scan('c', 'LR5', 'LR14') }}
    SET LR12 LR11 ; SET LR6 LR5 ; BEQ LR9 CR1 right_ready ;;
    ADD LR12 LR11 CR1 ; SET LR6 LR14 ;;
right_ready:
    {{ scan('d', 'LR5', 'LR6') }}
    {{ store() }}
    INC LR11 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 x_pair ;;
    INC LR14 1 ;;
    BLT.S LR14 LR15 channel ;;
    HALT ;;
