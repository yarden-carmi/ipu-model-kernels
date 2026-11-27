{% macro tap(y, x) %}
    SET LR5 LR1 ;;
    DEC LR5 1 ;;
    {% if x %}INC LR5 {{x}} ;;{% endif %}
    SET LR6 CR0 ; BLT.S LR5 CR0 skip_{{y}}_{{x}} ;;
    BGE.S LR5 {{cr.in0_d3}} skip_{{y}}_{{x}} ;;
channel_{{y}}_{{x}}:
    LD.MULT R0 LR4 {{cr.weights}} ;;
    LD.MULT.CYCLIC LR5 {{cr.transpose}} LR0 ;;
    MULT.RC.VE LR{{ 14 if y == 0 else 15 if y == 2 else 0 }} LR0 0 LR{{ 11 if y == 0 else 12 if y == 2 else 0 }} {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; ADD LR5 LR5 {{cr.in0_d3}} ; INC LR4 1 ; INC LR6 1 ; BLT.S LR6 {{cr.last_channel}} channel_{{y}}_{{x}} ;;
    B end_{{y}}_{{x}} ;;
skip_{{y}}_{{x}}:
    ADD LR4 LR4 {{cr.in0_d1}} ;;
end_{{y}}_{{x}}:
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; LD.MULT.CYCLIC LR0 {{cr.onehot}} LR0 ;;
transpose_channel:
    SET LR4 CR0 ;;
transpose_x:
    MULT.RC.VE LR0 CR0 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; SET LR5 LR1 ; SET LR6 CR0 ;;
transpose_y:
    LD.MULT R0 LR5 {{cr.in0}} ;;
    LD.MULT.CYCLIC LR6 {{cr.onehot}} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR5 1 ; INC LR6 1 ;;
    BLT.S LR6 LR9 transpose_y ;;
    ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_in0}}.L {{cr.transpose}} LR2 ;;
    INC LR2 1 ; INC LR4 1 ;;
    BLT.S LR4 {{cr.in0_d3}} transpose_x ;;
    ADD LR1 LR1 LR9 ; INC LR3 1 ;;
    BLT.S LR3 {{cr.in0_d1}} transpose_channel ;;
    SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ; INC LR13 192 ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    INC LR13 192 ; DEC LR14 1 ; INC LR15 1 ;;
    INC LR11 1 ; DEC LR12 1 ;;
x_loop:
    SET LR3 CR0 ; SET LR4 CR0 ;;
co_loop:
    LD.MULT.CYCLIC LR4 {{cr.weights}} LR0 ;;
    INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
{% for y in range(3) %}{% for x in range(3) %}{{tap(y, x)}}{% endfor %}{% endfor %}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.width}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{cr.out0_d1}} co_loop ;;
    INC LR1 1 ;;
    BLT.S LR1 {{cr.in0_d3}} x_loop ;;
    HALT ;;
