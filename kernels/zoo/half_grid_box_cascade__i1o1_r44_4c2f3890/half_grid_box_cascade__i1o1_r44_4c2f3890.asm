{# Fuse the two box stages: each axis contributes 3/4 of the center
   and 1/4 of the parity-selected, edge-clamped neighbor. #}
{% set w9 = cr.f9 if format == 'fp32' else cr.w9 %}
{% set w3 = cr.f3 if format == 'fp32' else cr.w3 %}
{% set w1 = cr.f1 if format == 'fp32' else cr.w1 %}
{% macro term(slot, weight, first=false) %}
    MULT.RC.VE {{ slot }} {{ weight }} 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
{% macro store() %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
{% endmacro %}
{% macro blend(center, vertical, horizontal, diagonal) %}
    {{ term(diagonal, w1, true) }}
    {{ term(horizontal, w3) }}
    {{ term(vertical, w3) }}
    {{ term(center, w9) }}
    {{ store() }}
{% endmacro %}
{% macro load_pair(a, b, slot_a, slot_b) %}
    LD.MULT.CYCLIC {{ a }} {{ cr.in0 }} {{ slot_a }} ;;
    LD.MULT.CYCLIC {{ b }} {{ cr.in0 }} {{ slot_b }} ;;
{% endmacro %}
{% macro scan(side) %}
    SET LR7 LR5 ; SET LR8 LR6 ; SET LR9 CR0 ;;
pair_{{ side }}:
    {{ load_pair('LR7', 'LR8', 'LR0', 'LR1') }}
    BEQ LR9 CR0 left_{{ side }} ;;
    SUB LR13 LR7 CR1 ; SUB LR14 LR8 CR1 ;;
    LD.MULT.CYCLIC LR13 {{ cr.in0 }} LR2 ;;
    ADD LR13 LR2 LR1 ;;
    LD.MULT.CYCLIC LR14 {{ cr.in0 }} LR13 ;;
    {{ blend('LR0', 'LR1', 'LR15', 'LR12') }}
    BEQ LR0 CR0 middle_{{ side }} ;;
left_{{ side }}:
    {{ blend('LR0', 'LR1', 'LR0', 'LR1') }}
middle_{{ side }}:
    {{ blend('LR0', 'LR1', 'LR11', 'LR3') }}
    {{ blend('LR11', 'LR3', 'LR0', 'LR1') }}
    INC LR7 1 ; INC LR8 1 ; INC LR9 1 ;;
    BGE.S LR9 {{ cr.pairs }} right_{{ side }} ;;
    ADD LR13 LR2 LR1 ;;
    {{ load_pair('LR7', 'LR8', 'LR2', 'LR13') }}
    {{ blend('LR11', 'LR3', 'LR2', 'LR13') }}
    BEQ LR0 CR0 pair_{{ side }} ;;
right_{{ side }}:
    {{ blend('LR11', 'LR3', 'LR11', 'LR3') }}
{% endmacro %}

    SET LR0 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR1 CR0 ;;
    INC LR11 {{ in0_d1 }} ; INC LR1 128 ;;
{% if oh == in0_d2 and ow == in0_d3 %}
    SET LR9 CR0 ;;
copy:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ;;
    {{ term('LR0', 'CR1', true) }}
    {{ store() }}
    {{ term('LR11', 'CR1', true) }}
    {{ store() }}
    INC LR5 1 ;;
    INC LR10 1 ; BLT.S LR10 {{ cr.pairs }} copy ;;
    SET LR10 CR0 ;;
    INC LR9 1 ; BLT.S LR9 {{ cr.in0_d2 }} copy ;;
{% else %}
    ADD LR2 LR1 LR1 ; ADD LR3 LR1 LR11 ;;
    ADD LR15 LR2 LR11 ; ADD LR13 LR2 LR1 ;;
    ADD LR12 LR13 LR11 ;;
y:
    SUB LR6 LR5 {{ cr.pairs }} ; BNE LR10 CR0 above ;;
    SET LR6 LR5 ;;
above:
    {{ scan('above') }}
    INC LR10 1 ; ADD LR6 LR5 {{ cr.pairs }} ;;
    BLT.S LR10 {{ cr.in0_d2 }} below ;;
    SET LR6 LR5 ;;
below:
    {{ scan('below') }}
    ADD LR5 LR5 {{ cr.pairs }} ; BLT.S LR10 {{ cr.in0_d2 }} y ;;
{% endif %}
    HALT ;;
