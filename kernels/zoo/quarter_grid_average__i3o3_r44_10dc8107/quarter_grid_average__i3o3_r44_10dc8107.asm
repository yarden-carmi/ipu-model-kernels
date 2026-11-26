{% macro sum_row(i) %}
    MULT.RC.VE LR{{ i }} {{ cr.weight_fp32 if format == 'fp32' else cr.weight }} 0 LR0 {{ cr.reduce4 }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if i == 3 else '' }} LR10 {{ cr.reduce4 }}.L {% if i > 3 %}; INC LR{{ i - 1 }} 2{% endif %} {% if i == 6 %}; INC LR7 1{% endif %} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR9 CR0 ; SET LR13 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR12 CR0 ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
plane:
    SET LR1 LR13 ; SET LR8 CR0 ;;
scanline:
    SET LR2 LR1 ; SET LR3 CR0 ; SET LR7 CR0 ;;
    SET LR4 LR14 ; ADD LR5 LR14 LR14 ;;
    ADD LR6 LR5 LR14 ;;
{% for i in range(3, 7) %}
    {% if i != 3 %}INC LR2 1 ;{% endif %} LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR{{ i }} ;;
{% endfor %}
window:
{% for i in range(3, 7) %}
    {{ sum_row(i) }}
{% endfor %}
    INC LR6 2 ; INC LR10 1 ; BLT.S LR7 {{ cr.out0_d3 }} window ;;
    INC.MODP2 LR11 CR1 2 ; INC LR1 2 ; INC LR8 1 ;;
    BNE LR11 CR0 next_scanline ;;
    {{ store(cr.full) }}
    INC LR12 1 ; SET LR10 CR0 ;;
next_scanline:
    BLT.S LR8 {{ cr.out0_d2 }} scanline ;;
    ADD LR13 LR13 {{ cr.h }} ; INC LR9 1 ;;
    BLT.S LR9 LR15 plane ;;
    BEQ LR11 CR0 done ;;
    {{ store(cr.tail) }}
done:
    HALT ;;
