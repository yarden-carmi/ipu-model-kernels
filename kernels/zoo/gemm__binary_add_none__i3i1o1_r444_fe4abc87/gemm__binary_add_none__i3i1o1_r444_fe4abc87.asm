{% macro coeff() %}LD.MULT.CYCLIC LR4 {{cr.w}} LR0 ; INC LR4 1{% endmacro %}
{% macro mac(s) %}MULT.RC.VE LR0 {{s}} 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; {{coeff()}}{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR5 CR0 ;;
    SET LR1 CR0 ; SET LR6 CR0 ; SET LR8 {{cr.rows}} ;;
    DEC LR5 1 ;;
pixel:
    SUB LR4 LR0 CR1 ; SET LR3 LR2 ;;
    {{coeff()}} ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD.FIRST ; {{coeff()}} ;;
    SET LR7 CR0 ;;
{% for j in range((s0_k + 127) // 128) %} INC LR7 {{ [128, s0_k - j * 128] | min }} ;; {% endfor %}
    ADD LR9 LR1 CR1 ; LD.MULT R0 LR3 {{cr.in0}} ;;
channel:
    {{mac('LR1')}} ;;
    {{mac('LR1')}} ;;
    {{mac('LR9')}} ;;
    {{mac('LR9')}} ; ADD LR3 LR3 {{cr.tiles}} ; DEC LR7 1 ;;
    BEQ LR7 CR0 channel_done ;;
    LD.MULT R0 LR3 {{cr.in0}} ; B channel ;;
channel_done:
    LD.MULT R0 LR5 {{cr.in1}} ; INC LR5 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{cr.full}}.L {{cr.qf_in1}}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{act_out0 | default('identity')}} {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR5 ; INC LR1 2 ; INC LR6 1 ; DEC LR8 1 ;;
    BNE LR6 {{cr.full_end}} next ;;
    SET LR6 CR0 ; SET LR1 CR0 ; INC LR2 1 ;;
next:
    BNE LR8 CR0 pixel ;;
    HALT ;;
