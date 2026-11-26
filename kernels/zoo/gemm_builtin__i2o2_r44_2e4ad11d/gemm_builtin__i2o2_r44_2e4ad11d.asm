{% macro coeff() -%}
LD.MULT R0 LR8 {{ cr.coeff }} ; INC LR8 1
{%- endmacro %}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR5 CR0 ;;
    DEC LR3 1 ; SET LR6 {{ cr.n }} ;;
{% set p = [4, 128 // in0_d2] | min %}
{% if p >= 2 %}
    SET LR1 CR0 ;;
    INC LR1 {{ in0_d2 }} ;;
{% endif %}
{% if p >= 3 %}
    SET LR10 CR0 ;;
    INC LR10 {{ 2 * in0_d2 }} ;;
{% endif %}
{% if p == 4 %}
    SET LR11 CR0 ;;
    INC LR11 {{ 3 * in0_d2 }} ;;
{% endif %}
channel:
    SET LR7 {{ cr.in0_d3 }} ; SET LR4 CR0 ;;
column:
    SUB LR8 LR5 CR1 ; SUB LR2 LR4 CR1 ; SET LR9 {{ cr.input_groups }} ;;
    {{ coeff() }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; {{ coeff() }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR2 1 ;;
    {{ coeff() }} ;;
inner:
{% for j in range(p) %}
{% set slot = ['LR0', 'LR1', 'LR10', 'LR11'][j] %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ coeff() }} {% if j == 0 %}; DEC LR9 1{% endif %} ;;
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ coeff() }} ;;
{% if j == p - 1 or (k % p != 0 and j == k % p - 1) %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; BEQ LR9 CR0 inner_done ;;
{% if j < p - 1 %}
    {{ coeff() }} ;;
{% endif %}
{% else %}
    MULT.RC.VV {{ slot }} R0 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; {{ coeff() }} ;;
{% endif %}
{% endfor %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; INC LR2 1 ;;
    {{ coeff() }} ; BEQ LR0 CR0 inner ;;
inner_done:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR3 1 ;;
    ADD LR4 LR4 {{ cr.input_groups }} ; DEC LR7 1 ; BNE LR7 CR1 column ;;
    ADD LR5 LR8 CR1 ; DEC LR6 1 ; BNE LR6 CR1 channel ;;
    HALT ;;
