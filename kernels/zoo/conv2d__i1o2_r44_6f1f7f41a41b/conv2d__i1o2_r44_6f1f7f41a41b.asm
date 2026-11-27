{# Transpose channel-lane input into output-height vectors for each vertical tap. #}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR15 CR0 ; SET LR14 CR0 ;;
    INC LR14 127 ; LD.MULT.CYCLIC LR0 {{cr.onehot}} LR15 ;;
tc:
    SET LR4 CR0 ;;
tx:
{% for ky in range(3) %}
    MULT.RC.VE LR15 CR0 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; SET LR5 CR0 ; SET LR6 LR4 ;;
{% for b in range(1, (cin + 127) // 128) %}    ADD LR6 LR6 LR4 ;;
{% endfor %}
{% if ky == 0 %}    SUB LR6 LR6 LR11 ;;{% elif ky == 2 %}    ADD LR6 LR6 LR11 ;;{% endif %}
ty_{{ky}}:
    SET LR7 LR5 ;;
{% if stride == 2 %}    ADD LR7 LR7 LR5 ;;
{% endif %}
{% if ky == 0 %}    DEC LR7 1 ;;
{% elif ky == 2 %}    INC LR7 1 ;;
{% endif %}
    BLT.S LR7 CR0 ty_skip_{{ky}} ;;
    BGE.S LR7 {{cr.in0_d2}} ty_skip_{{ky}} ;;
    ADD LR8 LR6 LR1 ;;
    LD.MULT R0 LR8 {{cr.in0}} ;;
    LD.MULT.CYCLIC LR5 {{cr.onehot}} LR15 ;;
    MULT.RC.VE LR15 LR3 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ;;
ty_skip_{{ky}}:
    INC LR5 1 ; ADD LR6 LR6 LR12 ; BLT.S LR5 LR9 ty_{{ky}} ;;
    ACTIVATE.QUANTIZE identity {{cr.height}}.L {{cr.qf_in0}}.L {{cr.transpose}} LR2 ;;
    INC LR2 1 ;;
{% endfor %}
    INC LR4 1 ;;
    BLT.S LR4 {{cr.in0_d3}} tx ;;
    INC LR3 1 ; BLT.S LR3 LR14 no_wrap ;;
    SET LR3 CR0 ; INC LR1 1 ;;
no_wrap:
    INC LR0 1 ;;
    BLT.S LR0 {{cr.in0_d1}} tc ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ;;
{% for i in range(0, 2 + 9 * cin, 255) %}    INC LR14 {{ [255, 2 + 9 * cin - i] | min }} ;;
{% endfor %}
co:
    SET LR3 CR0 ;;
ox:
    SET LR4 LR1 ;;
    LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ;;
    INC LR4 1 ;;
    MULT.RC.VE LR15 CR1 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ;;
{% for ky in range(3) %}{% for kx in range(3) %}
    SET LR5 LR3 ;;
{% if stride == 2 %}    ADD LR5 LR5 LR3 ;;
{% endif %}
{% if kx == 0 %}    DEC LR5 1 ;;
{% elif kx == 2 %}    INC LR5 1 ;;
{% endif %}
    BLT.S LR5 CR0 skip_{{ky}}_{{kx}} ;;
    BGE.S LR5 {{cr.in0_d3}} skip_{{ky}}_{{kx}} ;;
    ADD LR6 LR5 LR5 ;;
    ADD LR6 LR6 LR5 ;;
{% if ky %}    INC LR6 {{ky}} ;;
{% endif %}    SET LR7 CR0 ;;
ch_{{ky}}_{{kx}}:
    LD.MULT R0 LR4 {{cr.weights}} ;;
    LD.MULT.CYCLIC LR6 {{cr.transpose}} LR15 ;;
    MULT.RC.VE LR15 LR15 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR4 1 ; ADD LR6 LR6 LR13 ; INC LR7 1 ; BLT.S LR7 LR10 ch_{{ky}}_{{kx}} ;;
    B end_{{ky}}_{{kx}} ;;
skip_{{ky}}_{{kx}}:
    ADD LR4 LR4 {{cr.in0_d1}} ;;
end_{{ky}}_{{kx}}:
{% endfor %}{% endfor %}
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.height}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
    INC LR2 1 ; INC LR3 1 ;;
    BLT.S LR3 {{cr.out0_d3}} ox ;;
    ADD LR4 LR1 LR14 ;;
    DEC LR4 1 ;;
    LD.MULT R0 LR4 {{cr.weights}} ;;
    ADD LR1 LR1 LR14 ; INC LR0 1 ;;
    BLT.S LR0 {{cr.out0_d1}} co ;;
    HALT ;;
