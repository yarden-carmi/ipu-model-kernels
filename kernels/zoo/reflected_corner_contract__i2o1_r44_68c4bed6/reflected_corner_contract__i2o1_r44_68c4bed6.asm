{% macro tap(row, lane, weight) %}
    LD.MULT R0 {{ row }} {{ cr.in0 }} ;;
    MULT.EE {{ lane }} {{ weight }} 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.single }}.L ;;
{% endmacro %}
{% macro tap3(row, lane) %}
{% if format == 'fp32' %}
    {{ tap(row, lane, cr.f1) }}
    {{ tap(row, lane, cr.f1) }}
    {{ tap(row, lane, cr.f1) }}
{% else %}
    {{ tap(row, lane, cr.k3) }}
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR6 CR0 ; SET LR14 CR0 ;;
y_loop:
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
    // Divide each input x by two: row index and packed-lane offset.
    SET LR1 LR7 ; SET LR3 CR0 ; SET LR2 CR1 ;;
    INC LR2 1 ;;
xa_div:
    BLT.S LR1 LR2 xa_done ;;
    SUB LR1 LR1 LR2 ; INC LR3 1 ; BNE CR0 CR1 xa_div ;;
xa_done:
    SET LR12 LR9 ; SET LR13 LR10 ;;
    BEQ LR1 CR0 xa_lane_done ;;
    ADD LR12 LR12 {{ cr.in0_d2 }} ; ADD LR13 LR13 {{ cr.in0_d2 }} ;;
xa_lane_done:
    SET LR1 LR8 ; SET LR4 CR0 ;;
xb_div:
    BLT.S LR1 LR2 xb_done ;;
    SUB LR1 LR1 LR2 ; INC LR4 1 ; BNE CR0 CR1 xb_div ;;
xb_done:
    SET LR7 LR9 ; SET LR8 LR10 ;;
    BEQ LR1 CR0 xb_lane_done ;;
    ADD LR7 LR7 {{ cr.in0_d2 }} ; ADD LR8 LR8 {{ cr.in0_d2 }} ;;
xb_lane_done:
    MULT.EE LR0 CR0 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR5 CR0 ;;
channel:
    {{ tap3('LR3', 'LR12') }}
    {{ tap3('LR3', 'LR12') }}
    {{ tap3('LR3', 'LR12') }}
    {{ tap3('LR4', 'LR7') }}
    {{ tap3('LR3', 'LR13') }}
    {{ tap('LR4', 'LR8', cr.f1 if format == 'fp32' else cr.k1) }}
    ADD LR3 LR3 {{ cr.pitch }} ; ADD LR4 LR4 {{ cr.pitch }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.in0_d1 }} channel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; INC LR15 1 ;;
    BLT.S LR15 {{ cr.ow }} x_loop ;;
    INC LR14 1 ;;
    BLT.S LR14 LR11 y_loop ;;
    HALT ;;
