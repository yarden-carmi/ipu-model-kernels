{# Width lanes let a cyclic read align a whole horizontal window with AGG.MAX. #}
{% macro aggregate(x, ds, first='') %}
    MULT.RC.VE {{ x }} CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ first }} LR6 {{ ds }}.L
{%- endmacro %}

plane:
    SUB LR4 LR0 {{ cr.padding }} ; SET LR14 CR0 ;;
row:
    ADD LR8 LR4 {{ cr.k }} ; SET LR7 LR4 ; SET LR6 CR0 ;;
    BGE.S LR7 CR0 y_low_ready ;;
    SET LR7 CR0 ;;
y_low_ready:
    BLT.S LR8 {{ cr.in0_d2 }} y_high_ready ;;
    SET LR8 {{ cr.in0_d2 }} ;;
y_high_ready:
    ADD LR15 LR3 LR8 ; SUB LR5 LR0 {{ cr.padding }} ;;
pixel:
    ADD LR10 LR5 {{ cr.k }} ; SET LR9 LR5 ; ADD LR11 LR3 LR7 ;;
    BLT.S LR9 CR0 left_edge ;;
    BGE.S {{ cr.in0_d3 }} LR10 full_window ;;
    SET LR10 {{ cr.in0_d3 }} ; BEQ LR0 CR0 clipped_window ;;
left_edge:
    SET LR9 CR0 ;;
    BGE.S {{ cr.in0_d3 }} LR10 clipped_window ;;
    SET LR10 {{ cr.in0_d3 }} ;;
clipped_window:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; ADD LR13 LR9 CR1 ;;
    {{ aggregate('LR9', cr.one_lane, '.FIRST') }} ; BEQ LR13 LR10 clipped_next_row ;;
clipped_x:
    {{ aggregate('LR13', cr.one_lane) }} ;;
    INC LR13 1 ;;
    BLT.S LR13 LR10 clipped_x ;;
clipped_next_row:
    INC LR11 1 ; SET LR13 LR9 ;;
    BEQ LR11 LR15 advance_pixel ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; BEQ LR0 CR0 clipped_x ;;
full_window:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ;;
    {{ aggregate('LR9', cr.window_lanes, '.FIRST') }} ; INC LR11 1 ;;
    BEQ LR11 LR15 advance_pixel ;;
full_y:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ;;
    {{ aggregate('LR9', cr.window_lanes) }} ; INC LR11 1 ;;
    BLT.S LR11 LR15 full_y ;;
advance_pixel:
    INC LR6 1 ; ADD LR5 LR5 {{ cr.stride }} ;;
    BLT.S LR6 {{ cr.out0_d3 }} pixel ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.output_lanes }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR14 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    INC LR1 1 ; BLT.S LR14 {{ cr.out0_d2 }} row ;;
    ADD LR3 LR3 {{ cr.in0_d2 }} ; BLT.S LR1 LR2 plane ;;
    HALT ;;
