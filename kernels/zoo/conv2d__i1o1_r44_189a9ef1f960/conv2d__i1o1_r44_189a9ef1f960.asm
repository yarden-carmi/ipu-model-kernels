{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set cb = (cin + 127) // 128 %}
{% macro tap(y, x) %}
    BLT.S LR11 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR11 {{cr.input_hw}}.L skip_{{y}}_{{x}} ;;
    SET LR12 LR9 ;;
{% if x %}    INC LR12 {{x * cb}} ;; {% endif %}
{% for c in range(cb) %}
    LD.MULT R0 LR12 {{cr.in0}} ; SET LR14 CR0 ; SET LR13 CR0 ;;
    DEC LR14 1 ; INC LR13 {{ [128, cin - c * 128] | min - 1 }} ;;
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
{% if [128, cin - c * 128] | min > 1 %}
channels_{{y}}_{{x}}_{{c}}:
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR14 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ; DEC LR13 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    BLT.S CR0 LR13 channels_{{y}}_{{x}}_{{c}} ;;
{% endif %}
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR14 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR14 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ;;
{% if c + 1 < cb %}    INC LR12 1 ;; {% endif %}
{% endfor %}
    B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    ADD LR5 LR5 {{cr.skip_x}} ;;
end_{{y}}_{{x}}:
{% if x + 1 < kw %}    INC LR11 1 ;; {% endif %}
{% endmacro %}
{% macro tap_row(y) %}
    BLT.S LR8 CR0 skip_y_{{y}} ;;
    BGE.S LR8 {{cr.input_hw}}.H skip_y_{{y}} ;;
    SET LR11 LR2 ;;
{% for x in range(kw) %}{{tap(y,x)}}{% endfor %}
    B end_y_{{y}} ;;
skip_y_{{y}}:
    ADD LR5 LR5 {{cr.skip_y}} ;;
end_y_{{y}}:
{% if y + 1 < kh %}    INC LR8 1 ; INC LR9 {{in0_d3 * cb}} ;; {% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ;;
{% if padding %}    DEC LR1 {{padding}} ; DEC LR6 {{padding * in0_d3 * cb}} ;; {% endif %}
oy:
    SET LR2 CR0 ; SET LR7 LR6 ;;
{% if padding %}    DEC LR2 {{padding}} ; DEC LR7 {{padding * cb}} ;; {% endif %}
ox:
    SET LR4 CR0 ; SET LR5 CR0 ;;
block:
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ; SET LR8 LR1 ; SET LR9 LR7 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ;;
{% for y in range(kh) %}{{tap_row(y)}}{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 {{cr.blocks}} full_store ;;
    ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{cr.tail}}.L {{qo}} {{cr.out0}} LR3 ;;
    INC LR3 1 ; B next_pixel ;;
full_store:
    ACTIVATE.QUANTIZE {{act_out0|default('identity')}} {{ds}} {{qo}} {{cr.out0}} LR3 ;;
    INC LR3 1 ; B block ;;
next_pixel:
    INC LR2 {{stride}} ; INC LR7 {{stride * cb}} ;;
    BLT.S LR2 {{cr.ends}}.L ox ;;
    INC LR1 {{stride}} ; INC LR6 {{stride * in0_d3 * cb}} ;;
    BLT.S LR1 {{cr.ends}}.H oy ;;
    HALT ;;
