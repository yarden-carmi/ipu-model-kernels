{% set n = in0_d3 if axis == -1 else in0_d2 %}
{% set ic = (in0_d2 + 127) // 128 %}
{% set oc = (out0_d2 + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set one = cr.one ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set act = act_out0 | default('identity') %}
{% set fixed = 2 * n >= out and n < out and n <= 128 %}
{% set mant = (n * 16777216 * 2 + out) // (2 * out) %}
{% set weight_den = 'LR3' if fixed else cr.den %}

{% macro integer(reg, value) %}
    SET {{ reg }} CR0 ;;
{% for bit in range(25, -1, -1) %}
{% if value >= 2 ** bit %}
    ADD {{ reg }} {{ reg }} {{ reg }} ;;
{% if (value // 2 ** bit) % 2 %}
    INC {{ reg }} 1 ;;
{% endif %}
{% endif %}
{% endfor %}
{% endmacro %}

{% macro start() %}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
{% if n < out %}
    DEC LR7 {{ out - n }} ;;
{% elif n > out %}
    INC LR7 {{ n - out }} ;;
{% endif %}
    SET LR8 CR0 ;;
    INC LR8 26 ;;
{% endmacro %}

{% macro normalize(tag, address=false) %}
normalize_{{ tag }}:
    BLT.S LR7 {{ cr.den }} phase_{{ tag }} ;;
    SUB LR7 LR7 {{ cr.den }} ; INC LR6 1 {% if address %}; ADD LR12 LR12 {{ cr.stride }} {% endif %}; BEQ CR0 CR0 normalize_{{ tag }} ;;
phase_{{ tag }}:
{% endmacro %}

{% macro next_phase() %}
    ADD LR7 LR7 {{ cr.step }} ; INC LR5 2 ; INC LR8 8 ;;
{% endmacro %}

{% macro coefficient(tag) %}
    SET LR12 CR0 ; SET LR15 LR8 ; MULT.VE LR0 CR0 0 LR0 {{ one }} {{ qi }} ; ACC.ADD.FIRST ;;
weight_{{ tag }}:
    INC LR12 1 ; ADD LR13 LR13 LR13 ;;
    BLT.S LR13 {{ weight_den }} skip_{{ tag }} ;;
    SUB LR13 LR13 {{ weight_den }} ; LD.MULT R0 LR12 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ one }} {{ qi }} ; ACC.ADD ;;
skip_{{ tag }}:
    BLT.S LR12 LR14 weight_{{ tag }} ;;
{% for part in range(4) %}
    ACTIVATE.QUANTIZE identity {{ one }} {{ qi }} {{ cr.work }} LR15 ;;
{% if part < 3 %}
    LD.MULT R0 LR15 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ one }} {{ qi }} ; ACC.SUB ; INC LR15 1 ;;
{% endif %}
{% endfor %}
{% endmacro %}

{% macro round_frac(k) %}
round_{{ k }}:
    SET LR15 LR7 ;;
    INC.MODP2 LR15 CR0 {{ k }} ;;
    SUB LR10 LR7 LR15 ; SET LR9 CR0 ;;
    INC LR9 {{ 2 ** (k - 1) }} ;;
    BLT.S LR15 LR9 rounded ;;
    BNE LR15 LR9 up_{{ k }} ;;
    SET LR15 LR10 ;;
    INC.MODP2 LR15 CR0 {{ k + 1 }} ;;
    BEQ LR15 CR0 rounded ;;
up_{{ k }}:
    ADD LR10 LR10 LR9 ;;
    ADD LR10 LR10 LR9 ; BEQ CR0 CR0 rounded ;;
{% endmacro %}

    INC LR1 128 ; INC LR14 25 ; MULT.VE LR0 CR0 0 LR0 {{ one }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ one }} {{ qi }} {{ cr.work }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.work }} ;;
powers:
    INC LR12 1 ; MULT.VE LR1 CR1 0 LR0 {{ one }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ one }} {{ qi }} {{ cr.work }} LR12 ;;
    BLT.S LR12 LR14 powers ;;

{{ start() }}
{% if fixed %}
{{ integer('LR3', 33554432) }}
{{ integer('LR4', 16777216) }}
{{ integer('LR2', 2 * mant) }}
{{ integer('LR7', mant) }}
    SUB LR7 LR7 LR4 ;;
normalize_weights:
    BLT.S LR7 LR3 phase_weights ;;
    SUB LR7 LR7 LR3 ; INC LR6 1 ; BEQ CR0 CR0 normalize_weights ;;
phase_weights:
    BGE.S LR6 {{ cr.last }} next_weight ;;
    BLT.S LR7 CR1 next_weight ;;
    SET LR11 LR6 ;;
    BLT.S LR7 LR4 exponent ;;
    INC LR11 1 ;;
exponent:
{% for k in range(8, 1, -1) %}
    SET LR9 CR0 ;;
    INC LR9 {{ 2 ** (k - 2) }} ;;
    BGE.S LR11 LR9 round_{{ k }} ;;
{% endfor %}
{% for k in range(1, 9) %}
{{ round_frac(k) }}
{% endfor %}
rounded:
    SUB LR13 LR3 LR10 ;;
    BLT.S LR13 LR4 weight_a_ready ;;
    SET LR9 LR13 ;;
    INC.MODP2 LR9 CR0 2 ;;
    BEQ LR9 CR1 weight_a_down ;;
    SET LR15 CR0 ;;
    INC LR15 3 ;;
    BNE LR9 LR15 weight_a_ready ;;
    INC LR13 1 ; BEQ CR0 CR0 weight_a_ready ;;
weight_a_down:
    DEC LR13 1 ;;
weight_a_ready:
{% else %}
{{ normalize('weights') }}
    BGE.S LR6 {{ cr.last }} next_weight ;;
    BLT.S LR7 CR1 next_weight ;;
    SET LR13 {{ cr.den }} ;;
    SUB LR13 LR13 LR7 ;;
{% endif %}
{{ coefficient('a') }}
    INC LR8 4 ; SET LR13 {{ 'LR10' if fixed else 'LR7' }} ;;
{{ coefficient('b') }}
    DEC LR8 4 ;;
next_weight:
{% if fixed %}
    ADD LR7 LR7 LR2 ; INC LR5 2 ; INC LR8 8 ;;
{% else %}
{{ next_phase() }}
{% endif %}
    BLT.S LR5 {{ cr.den }} normalize_weights ;;
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;

{% macro dot(a, b, scalar, ds) %}
    SET LR15 LR8 ; LD.MULT R0 LR15 {{ cr.work }} ;;
{% for k in range(8) %}
    {% if k % 2 == 0 %}INC LR15 4 ; LD.MULT R0 LR15 {{ cr.work }} ; {% elif k < 7 %}DEC LR15 3 ; LD.MULT R0 LR15 {{ cr.work }} ; {% endif %}MULT.RC.VE {{ a if k % 2 == 0 else b }} LR0 0 LR0 {{ ds }} {{ qi }} ; {% if scalar %}{{ 'AGG.SUM.FIRST' if k == 0 else 'AGG.SUM' }} LR10 {{ one }}{% else %}{{ 'ACC.ADD.FIRST' if k == 0 else 'ACC.ADD' }}{% endif %} ;;
{% endfor %}
{% endmacro %}

{% macro gather(c, ds) %}
    SET LR10 CR0 ; SET LR14 CR0 ;;
    INC LR14 {{ [128, out0_d2 - 128 * c] | min }} ;;
{{ normalize('y' ~ c) }}
    BGE.S LR6 {{ cr.last }} copy_y{{ c }} ;;
    BLT.S LR7 CR1 copy_y{{ c }} ;;
    SET LR9 LR6 ;;
    INC LR9 1 ;;
{{ dot('LR6', 'LR9', true, one) }}
    BEQ CR0 CR0 next_y{{ c }} ;;
copy_y{{ c }}:
    MULT.RC.VE LR6 CR1 0 LR0 {{ one }} {{ qi }} ; AGG.SUM.FIRST LR10 {{ one }} ;;
next_y{{ c }}:
    INC LR10 1 ; ADD LR7 LR7 {{ cr.step }} ; INC LR8 8 ;;
    BLT.S LR10 LR14 normalize_y{{ c }} ;;
    ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}

{% macro blend(c, ds, copy) %}
{% if copy %}
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% else %}
    LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR0 ;;
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR1 ;;
{{ dot('LR0', 'LR1', false, ds) }}
{% endif %}
    ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR11 ;;
{% if c + 1 < oc %}
    INC LR11 1 ; INC LR12 1 ; INC LR9 1 ;;
{% endif %}
{% endmacro %}

{% if axis == -2 %}
outer:
{{ start() }}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
{% if ic > 1 %}
    SET LR12 LR2 ;;
    INC LR12 1 ; LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR1 ;;
{% endif %}
{% for c in range(oc) %}
{{ gather(c, tail if c + 1 == oc else full) }}
{% endfor %}
    INC LR2 {{ ic }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.outer }} outer ;;
{% else %}
outer:
{{ start() }}
    SET LR13 LR2 ; SET LR11 LR3 ;;
x:
    SET LR12 LR13 ;;
{{ normalize('x', true) }}
    SET LR13 LR12 ;;
    BGE.S LR6 {{ cr.last }} copy_x ;;
    BLT.S LR7 CR1 copy_x ;;
    ADD LR9 LR12 {{ cr.stride }} ;;
{% for c in range(oc) %}
{{ blend(c, tail if c + 1 == oc else full, false) }}
{% endfor %}
    BEQ CR0 CR0 next_x ;;
copy_x:
{% for c in range(oc) %}
{{ blend(c, tail if c + 1 == oc else full, true) }}
{% endfor %}
next_x:
{{ next_phase() }}
    INC LR11 {{ oc - (oc - 1) }} ;;
    BLT.S LR5 {{ cr.den }} x ;;
    SET LR3 LR11 ;;
    SET LR2 LR13 ;;
    ADD LR2 LR2 {{ cr.stride }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.outer }} outer ;;
{% endif %}
    HALT ;;
