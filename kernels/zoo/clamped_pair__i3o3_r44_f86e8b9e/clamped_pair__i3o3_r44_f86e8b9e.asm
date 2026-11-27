{% set n = in0_d3 if axis == -1 else in0_d2 %}
{% set ic = (in0_d3 + 127) // 128 %}
{% set oc = (out0_d3 + 127) // 128 %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set one = cr.one ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% set tail = cr.tail ~ '.L' %}
{% set act = act_out0 | default('identity') %}
{% macro start() %}
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
{% if n < out %}
    DEC LR7 {{ out - n }} ;;
{% elif n > out %}
    INC LR7 {{ n - out }} ;;
{% endif %}
    SET LR8 CR0 ;;
    INC LR8 21 ;;
{% endmacro %}
{% macro normalize(tag, vertical=false) %}
normalize_{{ tag }}:
    BLT.S LR7 {{ cr.den }} phase_{{ tag }} ;;
    SUB LR7 LR7 {{ cr.den }} ; INC LR6 1 {% if vertical %}; ADD LR11 LR11 {{ cr.rowstride }} {% endif %}; BEQ CR0 CR0 normalize_{{ tag }} ;;
phase_{{ tag }}:
{% endmacro %}
{% macro next_phase() %}
    ADD LR7 LR7 {{ cr.step }} ; INC LR5 2 ; INC LR8 4 ;;
{% endmacro %}
{% macro coefficient(tag) %}
    SET LR12 CR0 ; SET LR15 LR8 ; MULT.VE LR0 CR0 0 LR0 {{ one }} {{ qi }} ; ACC.ADD.FIRST ;;
weight_{{ tag }}:
    INC LR12 1 ; ADD LR13 LR13 LR13 ;;
    BLT.S LR13 {{ cr.den }} skip_{{ tag }} ;;
    SUB LR13 LR13 {{ cr.den }} ; LD.MULT R0 LR12 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ one }} {{ qi }} ; ACC.ADD ;;
skip_{{ tag }}:
    BLT.S LR12 LR14 weight_{{ tag }} ;;
    ACTIVATE.QUANTIZE identity {{ one }} {{ qi }} {{ cr.work }} LR15 ;;
    LD.MULT R0 LR15 {{ cr.work }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ one }} {{ qi }} ; ACC.SUB ;;
    INC LR15 1 ; ACTIVATE.QUANTIZE identity {{ one }} {{ qi }} {{ cr.work }} LR15 ;;
{% endmacro %}
    INC LR1 128 ; INC LR14 20 ; MULT.VE LR0 CR0 0 LR0 {{ one }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ one }} {{ qi }} {{ cr.work }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.work }} ;;
powers:
    INC LR12 1 ; MULT.VE LR1 CR1 0 LR0 {{ one }} {{ qi }} ; ACC.SUB ; ACTIVATE.QUANTIZE exp2 {{ one }} {{ qi }} {{ cr.work }} LR12 ;;
    BLT.S LR12 LR14 powers ;;
{{ start() }}
{{ normalize('weights') }}
    BGE.S LR6 {{ cr.last }} next_weight ;;
    BLT.S LR7 CR1 next_weight ;;
    SET LR13 {{ cr.den }} ;;
    SUB LR13 LR13 LR7 ;;
{{ coefficient('a') }}
    INC LR8 2 ; SET LR13 LR7 ;;
{{ coefficient('b') }}
    DEC LR8 2 ;;
next_weight:
{{ next_phase() }}
    BLT.S LR5 {{ cr.den }} normalize_weights ;;
{% macro dot(a, b, scalar, ds) %}
    SET LR15 LR8 ; LD.MULT R0 LR15 {{ cr.work }} ;;
{% for k in range(4) %}
    {% if k < 3 %}INC LR15 1 ; LD.MULT R0 LR15 {{ cr.work }} ; {% endif %}MULT.RC.VE {{ a if k < 2 else b }} LR0 0 LR0 {{ ds }} {{ qi }} ; {% if scalar %}{{ 'AGG.SUM.FIRST' if k == 0 else 'AGG.SUM' }} LR10 {{ one }}{% else %}{{ 'ACC.ADD.FIRST' if k == 0 else 'ACC.ADD' }}{% endif %} ;;
{% endfor %}
{% endmacro %}
{% macro horizontal(c, ds) %}
    SET LR10 CR0 ; SET LR14 CR0 ;;
    INC LR14 {{ [128, out0_d3 - 128 * c] | min }} ;;
{{ normalize('x' ~ c) }}
    BGE.S LR6 {{ cr.last }} copy_x{{ c }} ;;
    BLT.S LR7 CR1 copy_x{{ c }} ;;
    SET LR9 LR6 ;;
    INC LR9 1 ;;
{{ dot('LR6', 'LR9', true, one) }}
    BEQ CR0 CR0 next_x{{ c }} ;;
copy_x{{ c }}:
    MULT.RC.VE LR6 CR1 0 LR0 {{ one }} {{ qi }} ; AGG.SUM.FIRST LR10 {{ one }} ;;
next_x{{ c }}:
    INC LR10 1 ; ADD LR7 LR7 {{ cr.step }} ; INC LR8 4 ;;
    BLT.S LR10 LR14 normalize_x{{ c }} ;;
    ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
{% macro vertical(c, ds, copy) %}
{% if copy %}
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
{% else %}
    LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR0 ;;
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR1 ;;
{{ dot('LR0', 'LR1', false, ds) }}
{% endif %}
    ACTIVATE.QUANTIZE {{ act }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 {% if c + 1 < oc %}; INC LR12 1 ; INC LR9 1 {% endif %};;
{% endmacro %}
outer:
{{ start() }}
{% if axis == -1 %}
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
{% if ic > 1 %}
    SET LR12 LR2 ;;
    INC LR12 1 ; LD.MULT.CYCLIC LR12 {{ cr.in0 }} LR1 ;;
{% endif %}
{% for c in range(oc) %}
{{ horizontal(c, tail if c + 1 == oc else full) }}
{% endfor %}
    ADD LR2 LR2 {{ cr.rowstride }} ;;
    BLT.S LR2 {{ cr.plane }} no_wrap_x ;;
    SUB LR2 LR2 {{ cr.plane }} ;;
    INC LR2 {{ ic }} ;;
no_wrap_x:
{% else %}
    SET LR11 LR2 ;;
{{ normalize('y', true) }}
    SET LR12 LR11 ; SET LR9 LR11 ;;
    BGE.S LR6 {{ cr.last }} copy_y ;;
    BLT.S LR7 CR1 copy_y ;;
    ADD LR9 LR9 {{ cr.rowstride }} ;;
{% for c in range(oc) %}
{{ vertical(c, tail if c + 1 == oc else full, false) }}
{% endfor %}
    BEQ CR0 CR0 next_y ;;
copy_y:
{% for c in range(oc) %}
{{ vertical(c, tail if c + 1 == oc else full, true) }}
{% endfor %}
next_y:
{{ next_phase() }}
    BLT.S LR5 {{ cr.den }} normalize_y ;;
    INC LR2 {{ ic }} ;;
{% endif %}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.outer }} outer ;;
    HALT ;;
