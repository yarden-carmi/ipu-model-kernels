// Each 16-channel segment is wholly within one padded input row.
// Gather segments from successive patch positions into a dense output row.
{% macro scatter(offset) %}
    MULT.VE {{ offset }} CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD2 0 ;
{% endmacro %}

    INC LR12 128 ;;
phase:
    SET LR5 LR11 ; SET LR6 LR11 ; SET LR13 CR0 ;;
row:
    SET LR2 LR14 ; SET LR3 LR15 ; SET LR4 {{ cr.segments }} ;;
segment:
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR9 LR8 ;;
    {{ scatter('LR8') }} INC LR9 8 ;;
    ADDBI LRD2 8 ;;
    {{ scatter('LR9') }} INC LR7 16 ; INC LR8 16 ;;
    ADDBI LRD2 8 ; DEC LR4 1 ; BEQ LR7 {{ cr.out0_d2 }} next_position ;;
    BLT.S LR8 {{ cr.lane_limit }} segment_done ;;
    SET LR8 CR0 ; INC LR6 1 ; B segment_done ;;
next_position:
    SET LR7 CR0 ; SET LR8 CR0 ; ADD LR5 LR5 {{ cr.spatial_step }} ;;
    SET LR6 LR5 ;;
segment_done:
    BNE LR4 CR0 segment ;;
    LD.MULT R1 LR10 {{ cr.in1 }} ;;
    MULT.VE LR12 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR13 1 ;;
    BLT.S LR13 {{ cr.phase_rows }} row ;;
    ADD LR11 LR11 {{ cr.blocks }} ; BLT.S LR10 {{ cr.rows }} phase ;;
    HALT ;;
