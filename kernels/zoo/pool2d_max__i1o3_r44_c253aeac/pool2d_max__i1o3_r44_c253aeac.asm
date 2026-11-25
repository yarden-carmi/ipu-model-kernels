{% macro reduce(first='') %}MULT.VE LR12 CR1 0 LR12 {{ cr.channel_ds }}.L {{ cr.qf_in0 }}.L ; ACC.MAX{{ first }}{% endmacro %}
{% macro gather() %}MULT.EE LR9 CR1 0 LR12 {{ cr.channel_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD12 LRD10 7{% endmacro %}

    SET LR7 CR0 ;;
batch:
    SET LR3 CR0 ; SET LR5 {{ cr.out0_d2 }} ;;
    SUB LR3 LR3 {{ cr.padding }} ;;
out_y:
    SET LR4 CR0 ; SET LR6 CR0 ;;
    SUB LR4 LR4 {{ cr.padding }} ;;
out_x:
    ADD LR13 LR3 {{ cr.k }} ; ADD LR14 LR4 {{ cr.k }} ;;
    BLT.S LR13 {{ cr.in0_d2 }} y_end ;;
    SET LR13 {{ cr.in0_d2 }} ;;
y_end:
    BLT.S LR14 {{ cr.in0_d3 }} x_end ;;
    SET LR14 {{ cr.in0_d3 }} ;;
x_end:
    SET LR9 LR3 ; SET LR10 LR8 ; SET LR11 LR4 ;;
    BGE.S LR11 CR0 clip_top ;;
    SET LR11 CR0 ;;
clip_top:
    BGE.S LR9 CR0 seed ;;
    INC LR9 1 ; ADD LR10 LR10 {{ cr.in0_d3 }} ; B clip_top ;;
seed:
    # Seed from a real pixel, not zero: signed windows can be all negative.
    ADD LR12 LR10 LR11 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    SET LR12 CR0 ;;
    {{ reduce('.FIRST') }} ;;
window_y:
    SET LR11 LR4 ;;
    BGE.S LR11 CR0 window_x ;;
    SET LR11 CR0 ;;
window_x:
    ADD LR12 LR10 LR11 ; INC LR11 1 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    SET LR12 CR0 ;;
    {{ reduce() }} ; BLT.S LR11 LR14 window_x ;;
    INC LR9 1 ; ADD LR10 LR10 {{ cr.in0_d3 }} ;;
    BLT.S LR9 LR13 window_y ;;
    # A max is an input value, so staging in the input format is lossless.
    ACTIVATE.QUANTIZE identity {{ cr.channel_ds }}.L {{ cr.qf_in0 }}.L {{ cr.pooled }} LR6 ;;
    INC LR6 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    BLT.S LR6 {{ cr.out0_d3 }} out_x ;;

    SET LR9 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
channel:
    SET LR6 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
gather_x:
    LD.MULT R0 LR6 {{ cr.pooled }} ;;
    {{ gather() }} ;;
    INC LR6 1 ; ADDBI LRD10 1 ;;
    BLT.S LR6 {{ cr.out0_d3 }} gather_x ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR9 1 ;;
    BLT.S LR9 LR15 channel ;;

    DEC LR2 1 ;;
    BEQ LR2 CR0 done ;;
    DEC LR5 1 ; ADD LR3 LR3 {{ cr.stride }} ; ADD LR8 LR8 LR1 ;;
    BNE LR5 CR0 out_y ;;
    ADD LR8 LR8 LR0 ; B batch ;;
done:
    HALT ;;
