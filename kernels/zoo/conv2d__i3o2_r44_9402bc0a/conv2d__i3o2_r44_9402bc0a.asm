{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set width = in0_d3 %}
{% macro inc_large(reg, amount) %}
{% for i in range(0, amount, 255) %}
    INC {{ reg }} {{ [255, amount - i] | min }} ;;
{% endfor %}
{% endmacro %}
{% macro transpose_rows(tag, base) %}
    SET LR4 CR0 ; SET LR6 LR1 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
    SET LR12 CR0 ;;
    LD.MULT R0 LR6 {{ base }} ;;
{% if out0_d2 > 1 %}
    SET LR7 CR0 ;;
    {{ inc_large('LR7', out0_d2 - 2) }}
transpose_y_{{ tag }}:
    {{ inc_large('LR6', out0_d3 * ((out0_d1 + 127) // 128)) }}
    MULT.EE LR2 CR1 0 LR12 {{ ds }} {{ qo }} ; ACC.RESHAPE LRD8 LRD10 7 ; LD.MULT R0 LR6 {{ base }} ;;
    INC LR4 1 ; ADDBI LRD10 1 ; BLT.S LR4 LR7 transpose_y_{{ tag }} ;;
{% endif %}
    MULT.EE LR2 CR1 0 LR12 {{ ds }} {{ qo }} ; ACC.RESHAPE LRD8 LRD10 7 ;;
{% endmacro %}

{# Keep packed coordinates as a row index and a lane remainder. #}
{% macro advance(row, lane, delta, tag) %}
{% if delta // 128 %}
    INC {{ row }} {{ delta // 128 }} ;;
{% endif %}
{% if delta % 128 %}
    INC {{ lane }} {{ delta % 128 }} ;;
    BLT.S {{ lane }} LR15 no_wrap_{{ tag }} ;;
    DEC {{ lane }} 128 ; INC {{ row }} 1 ;;
no_wrap_{{ tag }}:
{% endif %}
{% endmacro %}

{% macro tap(y, x) %}
{% set tag = y ~ '_' ~ x %}
    BLT.S LR11 CR0 skip_{{ tag }} ;;
    BGE.S LR11 {{ cr.input_hw }}.L skip_{{ tag }} ;;
    SET LR12 LR9 ; ADD LR13 LR10 LR11 ; SET LR14 CR0 ;;
    BLT.S LR13 LR15 channels_{{ tag }} ;;
    DEC LR13 128 ; INC LR12 1 ;;
channels_{{ tag }}:
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; INC LR12 {{ in0_d2 }} ; INC LR14 1 ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR5 1 ; BLT.S LR14 {{ cr.in0_d1 }} channels_{{ tag }} ;;
    B end_{{ tag }} ;;
skip_{{ tag }}:
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
    {{ inc_large('LR5', kw * in0_d1) }}
end_y_{{ y }}:
{% if y + 1 < kh %}
    INC LR8 1 ;;
    INC LR9 1 ;;
{% endif %}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR15 CR0 ;;
    INC LR15 128 ;;
{% if padding %}
    DEC LR1 {{ padding }} ; DEC LR6 {{ padding }} ;;
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
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ qo }} {{ cr.tmp }} LR3 ;;
    B residual ;;
full_store:
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.tmp }} LR3 ;;
residual:
    LD.MULT R0 LR3 {{ cr.tmp }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qo }} ; ACC.SUB ;;
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qo }} {{ cr.res }} LR3 ;;
    INC LR3 1 ;;
    BLT.S LR4 {{ cr.blocks }} block ;;
next_pixel:
    INC LR2 {{ stride }} ;;
    BLT.S LR2 {{ cr.ends }}.L ox ;;
    INC LR1 {{ stride }} ;;
    INC LR6 {{ stride }} ;;
    BLT.S LR1 {{ cr.ends }}.H oy ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR14 CR0 ;;
transpose_channel:
    SET LR3 CR0 ;;
transpose_x:
    {{ transpose_rows('main', cr.tmp) }}
    ACTIVATE.QUANTIZE identity {{ cr.tail }}.H {{ qo }} {{ cr.trans }} LR5 ;;
    {{ transpose_rows('residual', cr.res) }}
    LD.MULT.CYCLIC LR5 {{ cr.trans }} LR12 ;;
    MULT.RC.VE LR12 CR1 0 LR12 {{ ds }} {{ qo }} ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.H {{ qo }} {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
    ADD LR1 LR1 {{ cr.blocks }} ; INC LR3 1 ;;
    SET LR7 CR0 ;;
    INC LR7 {{ out0_d3 }} ;;
    BLT.S LR3 LR7 transpose_x ;;
    SET LR1 LR14 ; INC LR2 1 ; INC LR0 1 ;;
    {% if out0_d1 > 128 %}
    SET LR7 CR0 ;;
    INC LR7 128 ;;
    BLT.S LR2 LR7 transpose_channel ;;
    SET LR2 CR0 ; INC LR14 1 ; INC LR1 1 ;;
    {% endif %}
    SET LR7 CR0 ;;
    {{ inc_large('LR7', out0_d1) }}
    BLT.S LR0 LR7 transpose_channel ;;
    HALT ;;
