{# The two box stages give [3/4, 1/4] on each axis, centered
   on the input pixel and biased toward the output's neighbor. #}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ;;
{% endmacro %}
{% macro term(idx, weight, first=false) %}
    MULT.RC.VE {{ idx }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro pixel() %}
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR2 ;;
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR3 ;;
    {{ term('LR3', w1, true) }}
    {{ term('LR2', w3) }}
    {{ term('LR1', w3) }}
    {{ term('LR0', w9) }}
    {{ store() }}
{% endmacro %}
{% macro scan(side) %}
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR10 CR0 ;;
x_{{ side }}:
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; SUB LR8 LR6 CR1 ; SUB LR9 LR7 CR1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR1 ; BNE LR10 CR0 left_{{ side }} ;;
    SET LR8 LR6 ; SET LR9 LR7 ;;
left_{{ side }}:
    {{ pixel() }}
    INC LR10 1 ; ADD LR8 LR6 CR1 ; ADD LR9 LR7 CR1 ;;
    BLT.S LR10 {{ cr.in0_d3 }} right_{{ side }} ;;
    SET LR8 LR6 ; SET LR9 LR7 ;;
right_{{ side }}:
    {{ pixel() }}
    INC LR6 1 ; INC LR7 1 ; BLT.S LR10 {{ cr.in0_d3 }} x_{{ side }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR12 CR0 ;;
{% if oh == in0_d2 and ow == in0_d3 %}
copy:
    LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
    {{ term('LR0', 'CR1', true) }}
    {{ store() }}
    INC LR4 1 ;;
    INC LR11 1 ; BLT.S LR11 {{ cr.in0_d3 }} copy ;;
    SET LR11 CR0 ;;
    INC LR13 1 ; BLT.S LR13 {{ cr.in0_d2 }} copy ;;
{% else %}
    SET LR1 {{ cr.slots }}.L ; SET LR2 {{ cr.slots }}.H ; SET LR11 CR0 ;;
    ADD LR3 LR2 LR1 ;;
y:
    SUB LR5 LR4 {{ cr.in0_d3 }} ; BNE LR11 CR0 above ;;
    SET LR5 LR4 ;;
above:
    {{ scan('above') }}
    INC LR11 1 ; ADD LR5 LR4 {{ cr.in0_d3 }} ;;
    BLT.S LR11 {{ cr.in0_d2 }} below ;;
    SET LR5 LR4 ;;
below:
    {{ scan('below') }}
    ADD LR4 LR4 {{ cr.in0_d3 }} ; BLT.S LR11 {{ cr.in0_d2 }} y ;;
{% endif %}
    HALT ;;
