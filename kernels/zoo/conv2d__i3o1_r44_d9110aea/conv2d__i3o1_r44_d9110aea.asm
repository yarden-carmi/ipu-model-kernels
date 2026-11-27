{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set width = in0_d3 %}
{% set pack = [4, 128 // in0_d3] | min %}
{% set span = pack * width %}

{# Keep packed coordinates as a row index and a lane remainder. #}
{% macro advance(row, lane, delta, tag) %}
{% if delta // span %}
    INC {{ row }} {{ delta // span }} ;;
{% endif %}
{% if delta % span %}
    INC {{ lane }} {{ delta % span }} ;;
    BLT.S {{ lane }} LR15 no_wrap_{{ tag }} ;;
    DEC {{ lane }} {{ span }} ; INC {{ row }} 1 ;;
no_wrap_{{ tag }}:
{% endif %}
{% endmacro %}

{% macro tap(y, x) %}
{% set tag = y ~ '_' ~ x %}
    BLT.S LR11 CR0 skip_{{ tag }} ;;
    BGE.S LR11 {{ cr.input_hw }}.L skip_{{ tag }} ;;
    SET LR12 LR9 ; ADD LR13 LR10 LR11 ; SET LR14 CR0 ;;
channels_{{ tag }}:
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; ADD LR12 LR12 {{ cr.plane }} ; INC LR14 1 ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR5 1 ; BLT.S LR14 {{ cr.in0_d1 }} channels_{{ tag }} ;;
    B end_{{ tag }} ;;
skip_{{ tag }}:
    ADD LR5 LR5 {{ cr.in0_d1 }} ;;
    ADD LR5 LR5 {{ cr.in0_d1 }} ;;
end_{{ tag }}:
{% if x + 1 < kw %}
    INC LR11 1 ;;
{% endif %}
{% endmacro %}

{% macro tap_row(y) %}
    BLT.S LR8 CR0 skip_y_{{ y }} ;;
    BGE.S LR8 {{ cr.input_hw }}.H skip_y_{{ y }} ;;
    SET LR11 LR2 ;;
{% for x in range(kw) %}{{ tap(y, x) }}{% endfor %}
    B end_y_{{ y }} ;;
skip_y_{{ y }}:
    ADD LR5 LR5 {{ cr.skip_y }} ;;
end_y_{{ y }}:
{% if y + 1 < kh %}
    INC LR8 1 ;;
    {{ advance('LR9', 'LR10', width, 'ky_' ~ y) }}
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR15 CR0 ;;
    INC LR15 {{ span }} ;;
{% if padding %}
    DEC LR1 {{ padding }} ; DEC LR6 {{ -((-padding * width) // span) }} ;;
{% if (-padding * width) % span %}
    INC LR7 {{ (-padding * width) % span }} ;;
{% endif %}
{% endif %}
oy:
    SET LR2 CR0 ;;
{% if padding %}    DEC LR2 {{ padding }} ;;{% endif %}
ox:
    SET LR4 CR0 ; SET LR5 CR0 ;;
block:
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; SET LR8 LR1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ; SET LR9 LR6 ; SET LR10 LR7 ;;
{% for y in range(kh) %}{{ tap_row(y) }}{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 {{ cr.blocks }} full_store ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; B next_pixel ;;
full_store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ qo }} {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; B block ;;
next_pixel:
    INC LR2 {{ stride }} ;;
    BLT.S LR2 {{ cr.ends }}.L ox ;;
    INC LR1 {{ stride }} ;;
    {{ advance('LR6', 'LR7', width * stride, 'oy') }}
    BLT.S LR1 {{ cr.ends }}.H oy ;;
    HALT ;;
