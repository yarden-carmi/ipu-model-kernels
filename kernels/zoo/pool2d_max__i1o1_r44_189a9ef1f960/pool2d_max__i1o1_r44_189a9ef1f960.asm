{% macro reduce(op) %}MULT.VE LR0 CR1 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.MAX{{ op }}{% endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
batch:
    SUB LR3 LR0 {{ cr.padding }} ; SET LR5 CR0 ; SET LR8 LR1 ;;
out_y:
    SUB LR4 LR0 {{ cr.padding }} ; SET LR6 CR0 ;;
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
    INC LR9 1 ; ADD LR10 LR10 {{ cr.in0_d3 }} ; BEQ LR0 CR0 clip_top ;;
seed:
    ADD LR12 LR10 LR11 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ reduce('.FIRST') }} ;;
window_y:
    SET LR11 LR4 ;;
    BGE.S LR11 CR0 window_x ;;
    SET LR11 CR0 ;;
window_x:
{% for i in range(3) %}
    ADD LR12 LR10 LR11 ; INC LR11 1 ;;
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ reduce('') }} ; BGE.S LR11 LR14 next_y ;;
{% endfor %}
    BEQ LR0 CR0 window_x ;;
next_y:
    INC LR9 1 ; ADD LR10 LR10 {{ cr.in0_d3 }} ;;
    BLT.S LR9 LR13 window_y ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    BLT.S LR6 {{ cr.out0_d3 }} out_x ;;
    INC LR5 1 ; ADD LR3 LR3 {{ cr.stride }} ; ADD LR8 LR8 {{ cr.vertical_step }} ;;
    BLT.S LR5 {{ cr.out0_d2 }} out_y ;;
    INC LR2 1 ; ADD LR1 LR1 LR15 ;;
    BLT.S LR2 {{ cr.out0_d0 }} batch ;;
    HALT ;;
