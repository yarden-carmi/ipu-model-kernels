{% macro reduce(op) %}MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX{{ op }}{% endmacro %}
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
    ADD LR12 LR10 LR11 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    {{ reduce('.FIRST') }} ;;
window_y:
    SET LR11 LR4 ;;
    BGE.S LR11 CR0 window_x ;;
    SET LR11 CR0 ;;
window_x:
    ADD LR12 LR10 LR11 ; LD.MULT R0 LR12 {{ cr.in0 }} ; INC LR11 1 ;;
    {{ reduce('') }} ; BLT.S LR11 LR14 window_x ;;
    INC LR9 1 ; ADD LR10 LR10 {{ cr.in0_d3 }} ;;
    BLT.S LR9 LR13 window_y ;;
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    BLT.S LR6 {{ cr.out0_d3 }} out_x ;;
    INC LR5 1 ; ADD LR3 LR3 {{ cr.stride }} ; SET LR9 CR0 ;;
advance_y:
    ADD LR8 LR8 {{ cr.in0_d3 }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.stride }} advance_y ;;
    BLT.S LR5 {{ cr.out0_d2 }} out_y ;;
    SET LR1 CR0 ; SET LR2 CR0 ; SET LR5 CR1 ;;
    ADD LR5 LR5 LR5 ;;
    ADD LR5 LR5 LR5 ;;
    ADD LR5 LR5 LR5 ;;
    ADD LR5 LR5 LR5 ;;
    ADD LR5 LR5 LR5 ;;
    ADD LR5 LR5 LR5 ;;
    ADD LR5 LR5 LR5 ;;
channel:
    SET LR3 CR0 ;;
transpose_row:
    SET LR4 CR0 ;;
transpose_lane:
    BGE.S LR3 LR7 write_last ;;
    LD.MULT.CYCLIC LR3 {{ cr.tmp }} LR0 ;;
    MULT.RC.VE LR2 CR1 0 LR0 {{ cr.single }}.L {{ cr.qf_in0 }}.L ; AGG.MAX.FIRST LR4 {{ cr.single }}.L ;;
    INC LR3 1 ; INC LR4 1 ;;
    BLT.S LR4 LR5 transpose_lane ;;
write_row:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR3 LR7 transpose_row ;;
    BEQ LR0 CR0 next_channel ;;
write_last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.single }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
next_channel:
    INC LR2 1 ;;
    BLT.S LR2 LR15 channel ;;
    HALT ;;
