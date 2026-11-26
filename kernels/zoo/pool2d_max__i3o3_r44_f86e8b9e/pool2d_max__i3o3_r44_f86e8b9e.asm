{% macro reduce(op, mult) %}
    MULT.{{ mult }} LR10 CR1 0 LR0 {{ cr.full_window }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ op }} LR9 {{ cr.full_window }}.L
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 {{ cr.in0_d1 }} ;;
plane:
    SUB LR3 LR0 {{ cr.padding }} ; SET LR13 LR1 ; SET LR4 CR0 ;;
    # LR13 is the input row at y=0 until the output's y origin reaches zero.
output_row:
    ADD LR6 LR3 {{ cr.k }} ; SET LR5 LR3 ; SET LR7 LR13 ;;
    SET LR12 CR0 ; BLT.S LR6 {{ cr.in0_d2 }} clip_top ;;
    SET LR6 {{ cr.in0_d2 }} ;;
clip_top:
    BGE.S LR5 CR0 input_row ;;
    SET LR5 CR0 ;;
input_row:
    LD.MULT R0 LR7 {{ cr.in0 }} ; SUB LR8 LR0 {{ cr.padding }} ; SET LR9 CR0 ;;
window:
    ADD LR11 LR8 {{ cr.k }} ; SET LR10 LR8 ;;
    BLT.S LR8 CR0 left_edge ;;
    BLT.S {{ cr.in0_d3 }} LR11 right_edge ;;
    BEQ LR12 CR0 seed_full ;;
    {{ reduce('', 'VE') }} ; BEQ LR0 CR0 next_window ;;
seed_full:
    {{ reduce('.FIRST', 'VE') }} ; BEQ LR0 CR0 next_window ;;
left_edge:
    SET LR10 CR0 ;;
    BGE.S {{ cr.in0_d3 }} LR11 edge ;;
right_edge:
    SET LR11 {{ cr.in0_d3 }} ;;
edge:
    # Broadcast only real edge pixels, so padding cannot win a signed max.
    BNE LR12 CR0 edge_max ;;
    {{ reduce('.FIRST', 'EE') }} ;;
    INC LR10 1 ;;
    BGE.S LR10 LR11 next_window ;;
edge_max:
    {{ reduce('', 'EE') }} ;;
    INC LR10 1 ;;
    BLT.S LR10 LR11 edge_max ;;
next_window:
    ADD LR8 LR8 {{ cr.stride }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d3 }} window ;;
    INC LR5 1 ; ADD LR7 LR7 {{ cr.in0_d1 }} ; SET LR12 CR1 ;;
    BLT.S LR5 LR6 input_row ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR4 1 ;;
    BGE.S LR4 {{ cr.out0_d2 }} next_plane ;;
    # Advance the clamped input origin by one channel group per real y step.
    ADD LR6 LR3 {{ cr.stride }} ; SET LR5 LR3 ;;
    BGE.S LR5 CR0 advance_y ;;
    SET LR5 CR0 ;;
advance_y:
    BGE.S LR5 LR6 y_ready ;;
    INC LR5 1 ; ADD LR13 LR13 {{ cr.in0_d1 }} ;;
    BEQ LR0 CR0 advance_y ;;
y_ready:
    SET LR3 LR6 ; BEQ LR0 CR0 output_row ;;
next_plane:
    INC LR1 1 ;;
    BLT.S LR1 LR14 plane ;;
    SET LR5 CR1 ;;
next_batch:
    BGE.S LR5 {{ cr.in0_d2 }} batch_ready ;;
    ADD LR1 LR1 {{ cr.in0_d1 }} ; INC LR5 1 ;;
    BEQ LR0 CR0 next_batch ;;
batch_ready:
    ADD LR14 LR1 {{ cr.in0_d1 }} ; BLT.S LR1 LR15 plane ;;
    HALT ;;
