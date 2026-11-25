// A one-element aggregation routes each weighted corner directly to its
// packed output lane. No intermediate quantization is needed.
{% set w9 = cr.f9 if format == 'fp32' else cr.k9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.k3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.k1 %}
{% macro tap(row, lane, weight, acc) %}
    LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
    MULT.EE {{ lane }} {{ weight }} 0 LR0 {{ cr.scalar_ds }}.L {{ cr.qf_in0 }}.L ; {{ acc }} LR7 {{ cr.scalar_ds }}.L ;;
{% endmacro %}

{% macro pixel(lane, other_lane, other_top, other_bottom) %}
    {{ tap('LR3', lane, w9, 'AGG.SUM.FIRST') }}
    {{ tap(other_top, other_lane, w3, 'AGG.SUM') }}
    {{ tap('LR4', lane, w3, 'AGG.SUM') }}
    {{ tap(other_bottom, other_lane, w1, 'AGG.SUM') }}
    INC LR7 1 ;;
{% endmacro %}

{% macro scan(tag) %}
    SET LR3 LR1 ; SET LR4 LR2 ; SET LR9 {{ cr.pitch }} ;;
{{ tag }}_pair:
    BEQ LR9 {{ cr.pitch }} {{ tag }}_left_edge ;;
    SUB LR5 LR3 CR1 ; SUB LR6 LR4 CR1 ; SET LR11 LR13 ; BNE CR0 CR1 {{ tag }}_left_ready ;;
{{ tag }}_left_edge:
    SET LR5 LR3 ; SET LR6 LR4 ; SET LR11 LR15 ;;
{{ tag }}_left_ready:
    {{ pixel('LR15', 'LR11', 'LR5', 'LR6') }}
    {{ pixel('LR15', 'LR13', 'LR3', 'LR4') }}
    {{ pixel('LR13', 'LR15', 'LR3', 'LR4') }}
    BEQ LR9 CR1 {{ tag }}_right_edge ;;
    ADD LR5 LR3 CR1 ; ADD LR6 LR4 CR1 ; SET LR11 LR15 ; BNE CR0 CR1 {{ tag }}_right_ready ;;
{{ tag }}_right_edge:
    SET LR5 LR3 ; SET LR6 LR4 ; SET LR11 LR13 ;;
{{ tag }}_right_ready:
    {{ pixel('LR13', 'LR11', 'LR5', 'LR6') }}
    INC LR3 1 ; INC LR4 1 ; DEC LR9 1 ;;
    BNE LR9 CR0 {{ tag }}_pair ;;
{% endmacro %}

{% macro drain(tag) %}
    BNE LR7 LR14 {{ tag }}_continue ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.packed }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; SET LR7 CR0 ;;
{{ tag }}_continue:
{% endmacro %}

    SET LR0 CR0 ; SET LR10 CR0 ; SET LR12 CR0 ;;
batch:
    SET LR15 CR0 ; SET LR13 {{ cr.packed }}.H ;;
channel:
    SET LR1 LR12 ; SET LR7 CR0 ; SET LR8 {{ cr.scalar_ds }}.H ;;
source_y:
    SET LR2 LR1 ; BEQ LR8 {{ cr.scalar_ds }}.H upper_ready ;;
    SUB LR2 LR1 {{ cr.pitch }} ;;
upper_ready:
    {{ scan('upper') }}
    SET LR2 LR1 ; BEQ LR8 CR1 lower_ready ;;
    ADD LR2 LR1 {{ cr.pitch }} ;;
lower_ready:
    {{ scan('lower') }}
    {{ drain('lower') }}
    ADD LR1 LR1 {{ cr.pitch }} ; DEC LR8 1 ;;
    BNE LR8 CR0 source_y ;;
    INC LR15 1 ; INC LR13 1 ;;
    BNE LR15 {{ cr.packed }}.H channel ;;
    SET LR12 LR1 ; BNE LR1 {{ cr.input_rows }} batch ;;
    HALT ;;
