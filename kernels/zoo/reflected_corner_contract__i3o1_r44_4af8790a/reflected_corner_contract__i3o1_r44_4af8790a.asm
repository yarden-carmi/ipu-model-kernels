// Gather a channel vector for each source pixel before applying the stencil.
// R0 holds one packed input row; the scalar broadcast feeds a single scatter.
    SET LR0 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR12 {{ cr.in0_d2 }} ;;
transpose_y:
    SET LR7 {{ cr.in0_d3 }} ;;
transpose_x:
    SET LR8 LR4 ; SET LR9 LR5 ; SET LR10 LR11 ;;
    SET LR3 CR0 ;;
transpose_c:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.EE LR9 CR1 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; DEC LR10 1 ; BEQ LR10 CR1 transpose_store ;;
    ADD LR8 LR8 LR1 ; BNE CR0 CR1 transpose_c ;;
transpose_store:
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_in0 }}.L {{ cr.transposed }} LR6 ;;
    INC LR6 1 ; INC LR5 1 ; DEC LR7 1 ; BNE LR7 CR1 transpose_x ;;
    DEC LR12 1 ; BEQ LR12 CR1 transpose_batch_end ;;
    BLT.S LR5 LR15 transpose_next ;;
    BNE CR0 CR1 transpose_advance_row ;;
transpose_batch_end:
    SET LR12 {{ cr.in0_d2 }} ;;
transpose_advance_row:
    INC LR4 1 ; SET LR5 CR0 ;;
transpose_next:
    DEC LR13 1 ; BNE LR13 CR1 transpose_y ;;

{% macro tap(row, weight, acc, store=false) %}
    LD.MULT R0 {{ row }} {{ cr.transposed }} ;;
    MULT.VE LR0 {{ weight }} 0 LR0 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; {{ acc }}{% if store %} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7{% endif %} ;;
{% endmacro %}

{% macro pixel() %}
    {% set w9 = cr.f9 if format == 'fp32' else cr.k9 %}
    {% set w3 = cr.f3 if format == 'fp32' else cr.k3 %}
    {% set w1 = cr.f1 if format == 'fp32' else cr.k1 %}
    {{ tap('LR3', w9, 'ACC.ADD.FIRST') }}
    {{ tap('LR5', w3, 'ACC.ADD') }}
    {{ tap('LR4', w3, 'ACC.ADD') }}
    {{ tap('LR6', w1, 'ACC.ADD', true) }}
    INC LR7 1 ;;
{% endmacro %}

{% macro scan(tag) %}
    SET LR3 LR1 ; SET LR4 LR2 ; SET LR9 {{ cr.in0_d3 }} ;;
{{ tag }}_x:
    SET LR5 LR3 ; SET LR6 LR4 ; BEQ LR9 {{ cr.in0_d3 }} {{ tag }}_left_ready ;;
    SUB LR5 LR3 CR1 ; SUB LR6 LR4 CR1 ;;
{{ tag }}_left_ready:
    {{ pixel() }}
    SET LR5 LR3 ; SET LR6 LR4 ; BEQ LR9 CR1 {{ tag }}_right_ready ;;
    ADD LR5 LR3 CR1 ; ADD LR6 LR4 CR1 ;;
{{ tag }}_right_ready:
    {{ pixel() }}
    INC LR3 1 ; INC LR4 1 ; DEC LR9 1 ; BNE LR9 CR1 {{ tag }}_x ;;
{% endmacro %}

    SET LR1 CR0 ; SET LR7 CR0 ;;
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
    ADD LR1 LR1 {{ cr.in0_d3 }} ; DEC LR8 1 ; BNE LR8 CR1 source_y ;;
    DEC LR14 1 ; BNE LR14 CR1 batch ;;
    HALT ;;
