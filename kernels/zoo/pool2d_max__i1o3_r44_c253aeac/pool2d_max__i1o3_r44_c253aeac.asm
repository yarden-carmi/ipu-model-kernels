{% macro reduce(suffix='') -%}
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.MAX{{ suffix }}
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ;;
batch:
    SET LR5 {{ cr.full }}.H ; SUB LR3 LR0 {{ cr.padding }} ;;
output_y:
    SET LR6 CR0 ; SUB LR8 LR0 {{ cr.padding }} ;;
output_x:
    ADD LR10 LR3 {{ cr.k }} ; ADD LR13 LR8 {{ cr.k }} ;;
    BLT.S LR10 {{ cr.in0_d2 }} clip_x_end ;;
    SET LR10 {{ cr.in0_d2 }} ;;
clip_x_end:
    BLT.S LR13 {{ cr.in0_d3 }} clip_top ;;
    SET LR13 {{ cr.in0_d3 }} ;;
clip_top:
    SET LR11 LR3 ; SET LR12 LR4 ;;
top_loop:
    BGE.S LR11 CR0 seed ;;
    INC LR11 1 ; ADD LR12 LR12 {{ cr.in0_d3 }} ; B top_loop ;;
seed:
    SET LR14 LR8 ; BGE.S LR8 CR0 seed_load ;;
    SET LR14 CR0 ;;
seed_load:
    ADD LR15 LR12 LR14 ; LD.MULT R0 LR15 {{ cr.in0 }} ;;
    {{ reduce('.FIRST') }} ;;
window_y:
    SET LR14 LR8 ; BGE.S LR8 CR0 window_x ;;
    SET LR14 CR0 ;;
window_x:
    ADD LR15 LR12 LR14 ; LD.MULT R0 LR15 {{ cr.in0 }} ; INC LR14 1 ;;
    {{ reduce() }} ; BLT.S LR14 LR13 window_x ;;
    INC LR11 1 ; ADD LR12 LR12 {{ cr.in0_d3 }} ;;
    BLT.S LR11 LR10 window_y ;;
    # A maximum is already representable in the input format.
    ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_in0 }}.L {{ cr.strip }} LR6 ;;
    INC LR6 1 ; ADD LR8 LR8 {{ cr.stride }} ;;
    BLT.S LR6 {{ cr.out0_d3 }} output_x ;;

    # Gather each channel of the pooled strip into consecutive width lanes.
    SET LR11 CR0 ;;
channel:
    SET LR6 CR0 ;;
width:
    LD.MULT R0 LR6 {{ cr.strip }} ;;
    MULT.EE LR11 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.MAX.FIRST LR6 {{ cr.valid }}.H ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.out0_d3 }} width ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR11 1 ;;
    BLT.S LR11 LR7 channel ;;
    DEC LR5 1 ; ADD LR3 LR3 {{ cr.stride }} ;;
    BEQ LR5 CR0 next_batch ;;
    ADD LR4 LR4 {{ cr.vertical_step }} ; B output_y ;;
next_batch:
    DEC LR1 1 ;;
    BEQ LR1 CR0 done ;;
    ADD LR4 LR4 LR9 ; B batch ;;
done:
    HALT ;;
