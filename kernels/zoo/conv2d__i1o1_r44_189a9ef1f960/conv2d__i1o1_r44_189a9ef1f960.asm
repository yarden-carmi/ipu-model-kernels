{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% macro tap(y, x) %}
    BLT.S LR8 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR8 {{cr.input_hw}}.H skip_{{y}}_{{x}} ;;
    BLT.S LR11 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR11 {{cr.input_hw}}.L skip_{{y}}_{{x}} ;;
    SET LR12 LR9 ;;
{% for c in range((in0_d1 + 127)//128) %}
{% set lanes = [128, in0_d1 - c * 128] | min %}
    LD.MULT R0 LR12 {{cr.in0}} ; SET LR13 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    DEC LR13 1 ; INC LR12 1 ;;
{% if lanes > 1 %}
    INC LR15 {{lanes - 2}} ;;
{% endif %}
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
{% if lanes > 1 %}
channel_{{y}}_{{x}}_{{c}}:
    MULT.RC.VE LR0 LR13 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR13 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ; INC LR14 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ; BLT.S LR14 LR15 channel_{{y}}_{{x}}_{{c}} ;;
{% endif %}
    MULT.RC.VE LR0 LR13 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR13 1 ; INC LR5 1 ; LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ;;
{% endfor %}
    B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    ADD LR5 LR5 {{cr.skip_y}} ;;
end_{{y}}_{{x}}:
{% if x + 1 < kw %}
    INC LR11 1 ; ADD LR9 LR9 {{cr.plane}} ;;
{% endif %}
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR6 CR0 ;;
{% if padding %}    DEC LR1 {{padding}} ; DEC LR6 {{padding * (in0_d3 + 1) * ((in0_d1 + 127)//128)}} ;;{% endif %}
oy:
    SET LR2 CR0 ;;
{% if padding %}    DEC LR2 {{padding}} ;;{% endif %}
ox:
    SET LR4 CR0 ; SET LR5 CR0 ;;
block:
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ; SET LR8 LR1 ; SET LR9 LR6 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{cr.weights}} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ; INC LR5 1 ;;
{% for y in range(kh) %}
    SET LR11 LR2 ;;
{% for x in range(kw) %}{{tap(y,x)}}{% endfor %}
{% if y + 1 < kh %}    INC LR8 1 ; INC LR9 {{(in0_d3 - kw + 1) * ((in0_d1 + 127)//128)}} ;;{% endif %}
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 {{cr.blocks}} full_store ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.tail}}.L {{qo}} {{cr.out0}} LR3 ;;
    INC LR3 1 ; B next_pixel ;;
full_store:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{ds}} {{qo}} {{cr.out0}} LR3 ;;
    INC LR3 1 ; B block ;;
next_pixel:
    INC LR2 {{stride}} ; INC LR6 {{stride * ((in0_d1 + 127)//128)}} ;;
    BLT.S LR2 {{cr.ends}}.L ox ;;
{% set row_step = (stride * in0_d3 - out0_d3 * stride) * ((in0_d1 + 127)//128) %}
    INC LR1 {{stride}} ; {{'INC' if row_step >= 0 else 'DEC'}} LR6 {{row_step | abs}} ;;
    BLT.S LR1 {{cr.ends}}.H oy ;;
    HALT ;;
