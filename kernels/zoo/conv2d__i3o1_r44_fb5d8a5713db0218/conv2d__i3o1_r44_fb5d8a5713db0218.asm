{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% macro tap(y, x) %}
    BLT.S LR8 CR0 skip_{{ y }}_{{ x }} ;;
    BGE.S LR8 {{ cr.input_hw }}.H skip_{{ y }}_{{ x }} ;;
    BLT.S LR9 CR0 skip_{{ y }}_{{ x }} ;;
    BGE.S LR9 {{ cr.input_hw }}.L skip_{{ y }}_{{ x }} ;;
    SET LR10 LR8 ; SET LR11 CR0 ;;
channels_{{ y }}_{{ x }}:
    LD.MULT R0 LR10 {{ cr.in0 }} ; INC LR11 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; INC LR10 {{ in0_d2 }} ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD ; INC LR5 1 ; BLT.S LR11 {{ cr.in0_d1 }} channels_{{ y }}_{{ x }} ;;
    B end_{{ y }}_{{ x }} ;;
skip_{{ y }}_{{ x }}:
    ADD LR5 LR5 {{ cr.in0_d1 }} ;;
end_{{ y }}_{{ x }}:
{% if x + 1 < kw %}    INC LR9 1 ;;{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
{% if padding %}    DEC LR1 {{ padding }} ;;{% endif %}
oy:
    SET LR2 CR0 ;;
{% if padding %}    DEC LR2 {{ padding }} ;;{% endif %}
ox:
    SET LR4 CR0 ; SET LR5 CR0 ;;
block:
    LD.MULT.CYCLIC LR5 {{ cr.weights }} LR0 ; SET LR8 LR1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; INC LR5 1 ;;
{% for y in range(kh) %}
    SET LR9 LR2 ;;
{% for x in range(kw) %}{{ tap(y, x) }}{% endfor %}
{% if y + 1 < kh %}    INC LR8 1 ;;{% endif %}
{% endfor %}
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
    BLT.S LR1 {{ cr.ends }}.H oy ;;
    HALT ;;
