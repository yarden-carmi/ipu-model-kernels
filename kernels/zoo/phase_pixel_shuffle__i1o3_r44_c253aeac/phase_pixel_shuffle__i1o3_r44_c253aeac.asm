{% macro phase(a) %}
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR10 CR0 ;;
    {% if a %}INC LR6 {{ a * s }} ;;{% endif %}
channel_{{ a }}:
    ADD LR4 LR14 LR7 ; SET LR8 CR0 ;;
    SET LR2 {{ cr.src_lo }} ; SET LR3 {{ cr.src_hi }} ;;
x_{{ a }}:
    LD.MULT R0 LR4 {{ cr.in0 }} ;;
    MULT.VE LR6 CR1 0 LR9 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 {{ 8 - s }} ;;
    ADDBI LRD2 {{ s }} ; ADD LR4 LR4 {{ cr.input_rows }} ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.in0_d3 }} x_{{ a }} ;;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR10 1 ; INC LR6 {{ s * s }} ;;
wrap_{{ a }}:
    BLT.S LR6 {{ cr.limit }} nowrap_{{ a }} ;;
    SUB LR6 LR6 {{ cr.limit }} ; INC LR7 1 ;;
    BEQ CR0 CR0 wrap_{{ a }} ;;
nowrap_{{ a }}:
    BLT.S LR10 {{ cr.channels }} channel_{{ a }} ;;
{% endmacro %}
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ;;
    SET LR5 CR0 ; SET LR9 CR0 ; SET LR13 CR0 ;;
    SET LR14 CR0 ;;
y_loop:
    {% for a in range(s) %}{{ phase(a) }}{% endfor %}
    ADD LR14 LR14 {{ cr.spatial_step }} ; INC LR13 1 ;;
    BLT.S LR13 {{ cr.spatial_rows }} y_loop ;;
    HALT ;;
