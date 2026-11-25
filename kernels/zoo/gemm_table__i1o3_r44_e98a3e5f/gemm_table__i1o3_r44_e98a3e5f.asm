{# Input cursor = XMEM row and lane offset within that row. #}
{% macro bias_digit(first) %}
    LD.MULT.CYCLIC LR2 {{ cr.bias_rows }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.store_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; INC LR2 1 ;;
{% endmacro %}
{% macro dot_digit() %}
    LD.MULT R0 LR4 {{ cr.weights }} ;;
    MULT.RC.VV LR6 R0 0 LR0 {{ cr.dot_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR9 {{ cr.dot_ds }}.L ; INC LR4 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR8 CR0 ; SET LR13 {{ cr.stripes }} ; SET LR2 CR0 ;;
{% for j in range(5) %}
    {% if j %}INC LR2 1 ; {% endif %}LD.LUT {{ j }} {{ cr.lut }} LR2 ;;
{% endfor %}
stripe:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR12 {{ cr.n }} ;;
group:
    {{ bias_digit(true) }}
    {{ bias_digit(false) }}
    SET LR9 CR0 ; SET LR11 {{ cr.opack }} ;;
channel:
    SET LR5 LR7 ; SET LR6 LR8 ; SET LR10 {{ cr.out0_d3 }} ;;
pixel:
    SET LR4 LR3 ; LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
{% for j in range(3) %}
    {{ dot_digit() }}
{% endfor %}
    ADD LR6 LR6 {{ cr.k }} ; INC LR9 1 ; DEC LR10 1 ;;
    BNE LR6 LR15 next_pixel ;;
    SET LR6 CR0 ; INC LR5 1 ;;
next_pixel:
    BNE LR10 CR0 pixel ;;
    SET LR3 LR4 ; DEC LR11 1 ; DEC LR12 1 ;;
    BEQ LR12 CR0 last_group ;;
    BNE LR11 CR0 channel ;;
{% macro store() %}
    ACTIVATE.QUANTIZE {{ 'generic' if act_out0 in ['hardswish', 'hardsigmoid', 'silu'] else act_out0 }} {{ cr.store_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
{% endmacro %}
    {{ store() }}
    B group ;;
last_group:
    {{ store() }}
    SET LR7 LR5 ; DEC LR13 1 ;;
{% if out0_d3 % (2 if in0_d1 <= 64 else 1) %}
    INC LR7 1 ;;
{% endif %}
    BNE LR13 CR0 stripe ;;
    HALT ;;
