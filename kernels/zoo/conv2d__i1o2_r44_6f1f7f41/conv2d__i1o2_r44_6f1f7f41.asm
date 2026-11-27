{# Accumulate each output height position in its own accumulator slot. #}
{% set cb = (cin + 127) // 128 %}
{% macro tap(y, x) %}
    SET LR14 LR7 ; SET LR8 LR3 ;;
    INC LR14 {{y}} ; INC LR8 {{x}} ;;
    BLT.S LR14 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR14 {{cr.in0_d2}} skip_{{y}}_{{x}} ;;
    BLT.S LR8 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR8 {{cr.in0_d3}} skip_{{y}}_{{x}} ;;
    ADD LR10 LR9 LR12 ;;
    INC LR10 {{(y * in0_d3 + x) * cb}} ;;
{% for c in range(cb) %}
    LD.MULT R0 LR10 {{cr.in0}} ;;
    LD.MULT.CYCLIC LR6 {{cr.weights}} LR15 ;;
    MULT.RC.VV LR15 R0 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR4 {{cr.full}}.L ; INC LR6 1 ; LD.MULT.CYCLIC LR6 {{cr.weights}} LR15 ;;
    MULT.RC.VV LR15 R0 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR4 {{cr.full}}.L ; INC LR6 1 ; INC LR10 1 ;;
{% endfor %}
    B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    INC LR6 {{2 * cb}} ;;
end_{{y}}_{{x}}:
{% endmacro %}
    SET LR15 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR5 CR0 ;;
channel:
    SET LR3 CR0 ; SET LR12 CR0 ;;
{% if padding %}    DEC LR3 {{padding}} ; DEC LR12 {{padding * cb}} ;;{% endif %}
column:
    SET LR4 CR0 ; SET LR7 CR0 ; SET LR9 CR0 ;;
{% if padding %}    DEC LR7 {{padding}} ; DEC LR9 {{padding * in0_d3 * cb}} ;;{% endif %}
height_loop:
    SET LR6 LR5 ;;
    LD.MULT R0 LR6 {{cr.weights}} ;;
    MULT.VE LR15 CR1 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM.FIRST LR4 {{cr.one}}.L ; INC LR6 1 ; LD.MULT R0 LR6 {{cr.weights}} ;;
    MULT.VE LR15 CR1 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; AGG.SUM LR4 {{cr.one}}.L ; INC LR6 1 ;;
{% for y in range(kh) %}{% for x in range(kw) %}{{tap(y,x)}}{% endfor %}{% endfor %}
    INC LR4 1 ; INC LR7 {{stride}} ; INC LR9 {{stride * in0_d3 * cb}} ;;
    BLT.S LR4 {{cr.out0_d2}} height_loop ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.outds}}.L {{cr.qf_out0}}.L {{cr.out0}} LR1 ;;
    INC LR1 1 ; INC LR3 {{stride}} ; INC LR12 {{stride * cb}} ;;
    BLT.S LR3 {{cr.xend}} column ;;
    INC LR5 {{2 * (1 + kh * kw * cb)}} ; INC LR2 1 ;;
    BLT.S LR2 {{cr.out0_d1}} channel ;;
    HALT ;;
