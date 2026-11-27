{% set w9 = cr.f9 if format == 'fp32' else cr.k9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.k3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.k1 %}
{% macro tap(row, lane, weight) %}
    LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
    MULT.EE {{ lane }} {{ weight }} 0 LR13 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR10 {{ cr.single }}.L ;;
{% endmacro %}
{% macro pixel(lane, other_lane, other_top, other_bottom) %}
    {{ tap('LR3', lane, w9) }}
    {{ tap(other_top, other_lane, w3) }}
    {{ tap('LR4', lane, w3) }}
    {{ tap(other_bottom, other_lane, w1) }}
    INC LR10 1 ;;
{% endmacro %}
{% macro scan(tag) %}
    MULT.EE LR13 CR0 0 LR13 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR3 LR1 ; SET LR4 LR2 ; SET LR9 {{ cr.pitch }} ;;
    SET LR10 CR0 ;;
{{ tag }}_pair:
    BEQ LR9 {{ cr.pitch }} {{ tag }}_left_edge ;;
    SUB LR11 LR3 CR1 ; SUB LR12 LR4 CR1 ; SET LR6 LR5 ; BNE CR0 CR1 {{ tag }}_left_ready ;;
{{ tag }}_left_edge:
    SET LR11 LR3 ; SET LR12 LR4 ; SET LR6 LR14 ;;
{{ tag }}_left_ready:
    {{ pixel('LR14', 'LR6', 'LR11', 'LR12') }}
    {{ pixel('LR14', 'LR5', 'LR3', 'LR4') }}
    {{ pixel('LR5', 'LR14', 'LR3', 'LR4') }}
    BEQ LR9 CR1 {{ tag }}_right_edge ;;
    ADD LR11 LR3 CR1 ; ADD LR12 LR4 CR1 ; SET LR6 LR14 ; BNE CR0 CR1 {{ tag }}_right_ready ;;
{{ tag }}_right_edge:
    SET LR11 LR3 ; SET LR12 LR4 ; SET LR6 LR5 ;;
{{ tag }}_right_ready:
    {{ pixel('LR5', 'LR6', 'LR11', 'LR12') }}
    INC LR3 1 ; INC LR4 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 {{ tag }}_pair ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ;;
{% endmacro %}
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR7 CR0 ;;
channel:
    ADD LR5 LR14 LR15 ; SET LR1 CR0 ; SET LR8 {{ cr.in0_d2 }} ;;
source_y:
    SET LR2 LR1 ; BEQ LR8 {{ cr.in0_d2 }} upper_ready ;;
    SUB LR2 LR1 {{ cr.pitch }} ;;
upper_ready:
    {{ scan('upper') }}
    SET LR2 LR1 ; BEQ LR8 CR1 lower_ready ;;
    ADD LR2 LR1 {{ cr.pitch }} ;;
lower_ready:
    {{ scan('lower') }}
    ADD LR1 LR1 {{ cr.pitch }} ; DEC LR8 1 ;;
    BNE LR8 CR0 source_y ;;
    INC LR14 1 ;;
    BLT.S LR14 LR15 channel ;;
    HALT ;;
