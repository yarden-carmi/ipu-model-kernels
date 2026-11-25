{% set width = cr.width_and_lanes ~ '.L' %}
{% set lanes = cr.width_and_lanes ~ '.H' %}
{% macro normalize(row, col, tag) %}
    BLT.S {{ col }} {{ cr.in0_d2 }} {{ tag }}_ready ;;
{{ tag }}_wrap:
    SUB {{ col }} {{ col }} {{ cr.in0_d2 }} ; ADD {{ row }} {{ row }} {{ width }} ;;
    BGE.S {{ col }} {{ cr.in0_d2 }} {{ tag }}_wrap ;;
{{ tag }}_ready:
{% endmacro %}
{% macro store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
{% endmacro %}

// Walk x planes in view storage order. LR4:LR5 is the padded
// physical base and unpadded column for flat offset x * (B * Y).
plane:
    SET LR12 {{ cr.out0_d0 }} ; SET LR13 LR15 ;;
batch:
    SET LR7 {{ cr.out0_d0 }} ; SET LR6 LR4 ; SET LR11 {{ cr.blocks }} ;;
    SUB LR7 LR7 LR12 ;;
    ADD LR7 LR7 LR5 ;;
    {{ normalize('LR6', 'LR7', 'batch') }}
    B lane_block ;;
lane_block:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR10 {{ lanes }} ;;
    BNE LR11 CR1 gather ;;
    SET LR10 {{ cr.tail }}.H ;;
gather:
    SET LR8 LR6 ; SET LR9 LR7 ;;
    BLT.S LR9 {{ lanes }} load_element ;;
lane_wrap:
    INC LR8 1 ; SUB LR9 LR9 {{ lanes }} ;;
    BGE.S LR9 {{ lanes }} lane_wrap ;;
load_element:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    // LRD2 contains eight copies of the destination lane. Each copy
    // receives the same broadcast scalar, so no other lane is changed.
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ;
    ADD LR7 LR7 {{ cr.out0_d0 }} ; DEC LR10 1 ;;
    {{ normalize('LR6', 'LR7', 'next_y') }}
    ADDBI LRD2 1 ; BNE LR10 CR0 gather ;;

    LD.MULT R0 LR13 {{ cr.in1 }} ; BNE LR11 CR1 full ;;
    {{ store(cr.tail ~ '.L') }}
    INC LR13 1 ; DEC LR12 1 ;;
    BEQ LR12 CR0 next_plane ;;
    ADD LR13 LR13 {{ cr.batch_jump }} ; B batch ;;
full:
    {{ store('CR15.L') }}
    INC LR13 1 ; DEC LR11 1 ; B lane_block ;;
next_plane:
    ADD LR4 LR4 LR1 ; ADD LR5 LR5 {{ cr.plane_cols }} ; ADD LR15 LR15 {{ cr.blocks }} ;;
    {{ normalize('LR4', 'LR5', 'plane') }}
    DEC LR14 1 ;;
    BNE LR14 CR0 plane ;;
    HALT ;;
