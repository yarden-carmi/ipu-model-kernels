{% macro reduce(op, width) %}
    MULT.VE LR10 CR1 0 LR0 {{ cr.full_window }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ op }} LR9 {{ width }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
plane:
    SUB LR3 LR0 {{ cr.padding }} ; SUB LR13 LR1 {{ cr.padding }} ; SET LR4 CR0 ;;
output_row:
    ADD LR6 LR3 {{ cr.k }} ; SET LR5 LR3 ; SET LR7 LR13 ;;
    SET LR12 CR0 ; BLT.S LR6 {{ cr.in0_d2 }} clip_top ;;
    SET LR6 {{ cr.in0_d2 }} ;;
clip_top:
    BGE.S LR5 CR0 input_row ;;
    INC LR5 1 ; INC LR7 1 ; BEQ LR0 CR0 clip_top ;;
input_row:
    LD.MULT R0 LR7 {{ cr.in0 }} ; SUB LR8 LR0 {{ cr.padding }} ; SET LR9 CR0 ;;
window:
    ADD LR11 LR8 {{ cr.k }} ; SET LR10 LR8 ;;
    BLT.S LR8 CR0 left_edge ;;
    BLT.S {{ cr.in0_d3 }} LR11 right_edge ;;
    BEQ LR12 CR0 seed_full ;;
    {{ reduce('', cr.full_window) }} ; BEQ LR0 CR0 next_window ;;
seed_full:
    {{ reduce('.FIRST', cr.full_window) }} ; BEQ LR0 CR0 next_window ;;
left_edge:
    SET LR10 CR0 ;;
    BGE.S {{ cr.in0_d3 }} LR11 edge ;;
right_edge:
    SET LR11 {{ cr.in0_d3 }} ;;
edge:
    BNE LR12 CR0 edge_max ;;
    {{ reduce('.FIRST', cr.single) }} ;;
    INC LR10 1 ;;
    BGE.S LR10 LR11 next_window ;;
edge_max:
    {{ reduce('', cr.single) }} ;;
    INC LR10 1 ;;
    BLT.S LR10 LR11 edge_max ;;
next_window:
    ADD LR8 LR8 {{ cr.stride }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d3 }} window ;;
    INC LR5 1 ; INC LR7 1 ; SET LR12 CR1 ;;
    BLT.S LR5 LR6 input_row ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR4 1 ; ADD LR3 LR3 {{ cr.stride }} ;;
    ADD LR13 LR13 {{ cr.stride }} ; BLT.S LR4 {{ cr.out0_d2 }} output_row ;;
    ADD LR1 LR1 {{ cr.in0_d2 }} ;;
    BLT.S LR1 LR15 plane ;;
    HALT ;;
