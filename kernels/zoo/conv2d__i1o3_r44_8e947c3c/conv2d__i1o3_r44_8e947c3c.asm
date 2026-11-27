{% set qi = cr.qf_in0 ~ '.L' %}
{% set qo = cr.qf_out0 ~ '.L' %}
{% set ds = cr.full ~ '.L' %}
{% set cb = (in0_d1 + 127) // 128 %}
{% set pack = [out0_d2, 128 // out0_d3] | min %}
{% macro tap(y, x) %}
    BLT.S LR8 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR8 {{cr.input_hw}}.H skip_{{y}}_{{x}} ;;
    BLT.S LR9 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR9 {{cr.input_hw}}.L skip_{{y}}_{{x}} ;;
{% for c in range(cb) %}
    LD.MULT R0 LR10 {{cr.in0}} ;;
    LD.MULT.CYCLIC LR11 {{cr.weights}} LR0 ; INC LR11 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ds}} {{qi}} ; AGG.SUM LR6 {{ds}} ; LD.MULT.CYCLIC LR11 {{cr.weights}} LR0 ; INC LR11 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ds}} {{qi}} ; AGG.SUM LR6 {{ds}} ; INC LR10 1 ;;
{% endfor %}
    B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    INC LR11 {{2 * cb}} ; INC LR10 {{cb}} ;;
end_{{y}}_{{x}}:
    INC LR9 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR7 CR0 ;;
output_channel:
    SET LR3 CR0 ; SET LR5 CR0 ;;
{% if padding %}
    DEC LR3 {{padding}} ; DEC LR5 {{padding * (in0_d3 + 1) * cb}} ;;
{% endif %}
output_group:
    LD.MULT R0 LR7 {{cr.weights}} ; SET LR6 CR0 ; SET LR12 CR0 ;;
    MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD.FIRST ; SET LR11 LR7 ;;
    INC LR11 1 ;;
    LD.MULT R0 LR11 {{cr.weights}} ;;
    MULT.VE LR0 CR1 0 LR0 {{ds}} {{qi}} ; ACC.ADD ;;
output_row:
    SET LR4 CR0 ;;
{% if padding %}    DEC LR4 {{padding}} ;; {% endif %}
output_pixel:
    SET LR8 LR3 ; SET LR10 LR5 ; SET LR11 LR7 ;;
    INC LR11 1 ;;
{% for y in range(kh) %}
    SET LR9 LR4 ;;
{% for x in range(kw) %}{{tap(y,x)}}{% endfor %}
{% if y + 1 < kh %}    INC LR8 1 ; INC LR10 {{(in0_d3 - kw) * cb}} ;; {% endif %}
{% endfor %}
    INC LR6 1 ; INC LR4 {{stride}} ; INC LR5 {{stride * cb}} ;;
    BLT.S LR4 {{cr.ends}}.L output_pixel ;;
    INC LR3 {{stride}} ; INC LR12 1 ;;
{% set step = (stride * in0_d3 - out0_d3 * stride) * cb %}
{% if step > 0 %}    INC LR5 {{step}} ;; {% elif step < 0 %}    DEC LR5 {{-step}} ;; {% endif %}
    BGE.S LR3 {{cr.ends}}.H last_group ;;
    BLT.S LR12 {{cr.pack}} output_row ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.row_ds}}.L {{qo}} {{cr.out0}} LR2 ;;
    INC LR2 1 ; B output_group ;;
last_group:
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.tail_ds}}.L {{qo}} {{cr.out0}} LR2 ;;
    INC LR2 1 ; INC LR1 1 ; INC LR7 {{2 + 2 * kh * kw * cb}} ;;
    BLT.S LR1 {{cr.out_channels}} output_channel ;;
    HALT ;;
