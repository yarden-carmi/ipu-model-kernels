// Assemble each output channel directly into its accumulator lane.
{% macro divide3(source, quotient, remainder, tag) %}
    SET {{ quotient }} CR0 ; SET {{ remainder }} {{ source }} ;;
{{ tag }}:
    DEC {{ remainder }} 3 ;;
    BLT.S {{ remainder }} CR0 {{ tag }}_done ;;
    INC {{ quotient }} 1 ; BNE CR0 CR1 {{ tag }} ;;
{{ tag }}_done:
    INC {{ remainder }} 3 ;;
{% endmacro %}

{% macro lane(remainder, tag) %}
    SET {{ remainder }} {{ remainder }} ;;
    BEQ {{ remainder }} CR0 {{ tag }}_zero ;;
    BEQ {{ remainder }} CR1 {{ tag }}_one ;;
    SET {{ remainder }} {{ cr.in0_d3 }} ;;
    ADD {{ remainder }} {{ remainder }} {{ cr.in0_d3 }} ; BNE CR0 CR1 {{ tag }}_zero ;;
{{ tag }}_one:
    SET {{ remainder }} {{ cr.in0_d3 }} ;;
{{ tag }}_zero:
{% endmacro %}

{% macro tap(row, lane, weight) %}
    LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
    MULT.EE {{ lane }} {{ weight }} 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.single }}.L ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR14 CR0 ;;
y_loop:
    // Divide output y by two and choose the reflected/clamped neighbour.
    SET LR1 LR14 ; SET LR9 CR0 ; SET LR2 CR1 ;;
    INC LR2 1 ;;
y_div:
    BLT.S LR1 LR2 y_div_done ;;
    SUB LR1 LR1 LR2 ; INC LR9 1 ; BNE CR0 CR1 y_div ;;
y_div_done:
    SET LR10 LR9 ;;
    BEQ LR1 CR0 y_even ;;
    INC LR10 1 ; SET LR1 LR14 ;;
    INC LR1 1 ;;
    BLT.S LR1 LR11 y_ready ;;
    SET LR10 LR9 ; BNE CR0 CR1 y_ready ;;
y_even:
    BEQ LR9 CR0 y_ready ;;
    DEC LR10 1 ;;
y_ready:
    SET LR15 CR0 ;;
x_loop:
    SET LR1 LR15 ; SET LR7 CR0 ; SET LR2 CR1 ;;
    INC LR2 1 ;;
x_div:
    BLT.S LR1 LR2 x_div_done ;;
    SUB LR1 LR1 LR2 ; INC LR7 1 ; BNE CR0 CR1 x_div ;;
x_div_done:
    SET LR8 LR7 ;;
    BEQ LR1 CR0 x_even ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.in0_d3 }} x_ready ;;
    SET LR8 LR7 ; BNE CR0 CR1 x_ready ;;
x_even:
    BEQ LR7 CR0 x_ready ;;
    DEC LR8 1 ;;
x_ready:
    MULT.EE LR0 CR0 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ; SET LR12 LR9 ; SET LR13 LR10 ;;
    {{ divide3('LR12', 'LR1', 'LR3', 'div_a') }}
    {{ divide3('LR13', 'LR2', 'LR4', 'div_b') }}
    {{ lane('LR3', 'lane_a') }}
    {{ lane('LR4', 'lane_b') }}
    ADD LR3 LR3 LR7 ; ADD LR4 LR4 LR7 ;;
channel:
    {{ tap('LR1', 'LR3', cr.f3 if format == 'fp32' else cr.k3) }}
    {{ tap('LR1', 'LR3', cr.f3 if format == 'fp32' else cr.k3) }}
    {{ tap('LR1', 'LR3', cr.f3 if format == 'fp32' else cr.k3) }}
    SUB LR3 LR3 LR7 ;;
    ADD LR3 LR3 LR8 ;;
    {{ tap('LR1', 'LR3', cr.f3 if format == 'fp32' else cr.k3) }}
    {{ tap('LR2', 'LR4', cr.f3 if format == 'fp32' else cr.k3) }}
    SUB LR4 LR4 LR7 ;;
    ADD LR4 LR4 LR8 ;;
    {{ tap('LR2', 'LR4', cr.f1 if format == 'fp32' else cr.k1) }}
    SUB LR3 LR3 LR8 ; SUB LR4 LR4 LR8 ;;
    ADD LR3 LR3 LR7 ; ADD LR4 LR4 LR7 ;;
    ADD LR1 LR1 {{ cr.channel_span }} ; ADD LR2 LR2 {{ cr.channel_span }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.in0_d1 }} channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR15 1 ;;
    BLT.S LR15 {{ cr.ow }} x_loop ;;
    INC LR14 1 ;;
    BLT.S LR14 LR11 y_loop ;;
    HALT ;;
