{# One accumulator lane per output column. All row/column bounds are runtime. #}
{% macro reduce(x, ds, op='') -%}
    MULT.RC.VE {{ x }} CR1 0 LR0 {{ ds }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ op }} LR7 {{ ds }}.L
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
plane:
    SUB LR4 LR0 {{ cr.padding }} ; SET LR5 CR0 ;;
output_y:
    SET LR8 LR4 ; ADD LR9 LR4 LR15 ;;
    BGE.S LR8 CR0 top_clipped ;;
    SET LR8 CR0 ;;
top_clipped:
    BLT.S LR9 {{ cr.in0_d2 }} bottom_clipped ;;
    SET LR9 {{ cr.in0_d2 }} ;;
bottom_clipped:
    ADD LR8 LR8 LR2 ; ADD LR9 LR9 LR2 ;;
    SUB LR6 LR0 {{ cr.padding }} ; SET LR7 CR0 ;;
output_x:
    SET LR10 LR8 ; ADD LR12 LR6 LR15 ; SET LR11 LR6 ;;
    BLT.S LR6 CR0 left_edge ;;
    BLT.S {{ cr.in0_d3 }} LR12 right_edge ;;

    # All k columns are in bounds: aggregate them in one word per row.
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    {{ reduce('LR6', cr.window, '.FIRST') }} ; INC LR10 1 ;;
    BGE.S LR10 LR9 next_x ;;
full_window:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    {{ reduce('LR6', cr.window) }} ; INC LR10 1 ;;
    BLT.S LR10 LR9 full_window ;;
    BEQ LR0 CR0 next_x ;;

left_edge:
    SET LR11 CR0 ;;
    BGE.S {{ cr.in0_d3 }} LR12 edge ;;
right_edge:
    SET LR12 {{ cr.in0_d3 }} ;;
edge:
    # Seed from a real pixel, never zero, so negative maxima survive padding.
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    {{ reduce('LR11', cr.single, '.FIRST') }} ;;
edge_y:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ; SET LR13 LR11 ;;
edge_x:
    {{ reduce('LR13', cr.single) }} ;;
    INC LR13 1 ;;
    BLT.S LR13 LR12 edge_x ;;
    INC LR10 1 ;;
    BLT.S LR10 LR9 edge_y ;;
next_x:
    INC LR7 1 ; ADD LR6 LR6 {{ cr.stride }} ;;
    BLT.S LR7 {{ cr.out0_d3 }} output_x ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; INC LR5 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    BLT.S LR5 {{ cr.out0_d2 }} output_y ;;
    ADD LR2 LR2 {{ cr.in0_d2 }} ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.planes }} plane ;;
    HALT ;;
