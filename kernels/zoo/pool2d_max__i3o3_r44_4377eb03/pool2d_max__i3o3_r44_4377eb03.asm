{# Reduce contiguous width windows directly into each output lane. #}
{% macro agg(first, ds) %}
    MULT.VE LR12 CR1 0 LR0 {{ cr.window }}.L {{ cr.qf_in0 }}.L ; AGG.MAX{{ first }} LR6 {{ ds }}.L
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
plane:
    SET LR3 CR0 ; SUB LR4 LR0 {{ cr.padding }} ;;
row:
    ADD LR5 LR4 {{ cr.k }} ; SET LR8 LR4 ;;
    BLT.S LR5 {{ cr.in0_d2 }} top ;;
    SET LR5 {{ cr.in0_d2 }} ;;
top:
    BGE.S LR8 CR0 row_setup ;;
    SET LR8 CR0 ;;
row_setup:
    SET LR6 CR0 ; SUB LR7 LR0 {{ cr.padding }} ;;
col:
    ADD LR10 LR7 {{ cr.k }} ; SET LR9 LR8 ;;
    BLT.S LR7 CR0 left ;;
    BLT.S {{ cr.in0_d3 }} LR10 right ;;
    SET LR12 LR7 ; ADD LR11 LR1 LR9 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ; INC LR9 1 ;;
    {{ agg('.FIRST', cr.window) }} ;;
    BGE.S LR9 LR5 next_col ;;
full_y:
    ADD LR11 LR1 LR9 ; LD.MULT R0 LR11 {{ cr.in0 }} ; INC LR9 1 ;;
    {{ agg('', cr.window) }} ; BLT.S LR9 LR5 full_y ;;
    BEQ LR0 CR0 next_col ;;
left:
    SET LR13 CR0 ;;
    BLT.S {{ cr.in0_d3 }} LR10 clip_right ;;
    BEQ LR0 CR0 edge_seed ;;
right:
    SET LR13 LR7 ;;
clip_right:
    SET LR10 {{ cr.in0_d3 }} ;;
edge_seed:
    ADD LR11 LR1 LR9 ; LD.MULT R0 LR11 {{ cr.in0 }} ; SET LR12 LR13 ;;
    {{ agg('.FIRST', cr.single) }} ;;
edge_x:
    {{ agg('', cr.single) }} ;;
    INC LR12 1 ;;
    BLT.S LR12 LR10 edge_x ;;
    INC LR9 1 ;;
    BGE.S LR9 LR5 next_col ;;
    ADD LR11 LR1 LR9 ; LD.MULT R0 LR11 {{ cr.in0 }} ; SET LR12 LR13 ;;
    BEQ LR0 CR0 edge_x ;;
next_col:
    INC LR6 1 ; ADD LR7 LR7 {{ cr.stride }} ;;
    BLT.S LR6 {{ cr.out0_d3 }} col ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR3 1 ; ADD LR4 LR4 {{ cr.stride }} ;;
    BLT.S LR3 {{ cr.out0_d2 }} row ;;
    ADD LR1 LR1 {{ cr.in0_d2 }} ; DEC LR15 1 ;;
    BLT.S LR0 LR15 plane ;;
    HALT ;;
