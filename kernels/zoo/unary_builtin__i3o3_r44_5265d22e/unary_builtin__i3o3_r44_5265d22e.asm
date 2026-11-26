{% macro decode() %}
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.input_ds }}.L {{ cr.qf_in0 }}.L
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13
{%- endmacro %}

    SET LR0 CR0 ;;
    SET LR8 CR0 ;;
    SET LR11 CR0 ;;
    SET LR13 CR0 ;;
channel:
    SET LR9 LR8 ;;
    SET LR10 CR0 ;;
plane:
    SET LR1 LR9 ;;
    ADD LR12 LR9 {{ cr.input_plane }} ; BNE LR6 {{ cr.lanes }} packed_group ;;

{# Full-width input rows transfer directly, one output row at a time. #}
direct_row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    INC LR1 1 ; {{ decode() }} ; ACC.ADD.FIRST ; {{ store(cr.full_ds) }} ;;
    INC LR13 1 ; BLT.S LR1 LR12 direct_row ;;
    B plane_done ;;

{# Narrow rows are concatenated in R_ACC before a single quantization. #}
packed_group:
    SET LR4 {{ cr.map_lo }} ;;
    SET LR5 {{ cr.map_hi }} ;;
    SET LR15 CR0 ;;
packed_row:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ; SET LR2 {{ cr.map_lo }} ;;
    SET LR3 {{ cr.map_hi }} ;;
    SET LR14 CR0 ;;
scatter:
    {{ decode() }} ; ACC.RESHAPE LRD2 LRD4 0 ;;
    ADDBI LRD2 8 ;;
    ADDBI LRD4 8 ;;
    INC LR14 8 ;;
    INC LR15 8 ; BLT.S LR14 LR6 scatter ;;
    INC LR1 1 ;;
    BEQ LR15 {{ cr.lanes }} packed_full ;;
    BLT.S LR1 LR12 packed_row ;;
    {{ store(cr.tail_ds) }} ;;
    INC LR13 1 ; B plane_done ;;
packed_full:
    {{ store(cr.full_ds) }} ;;
    INC LR13 1 ; BLT.S LR1 LR12 packed_group ;;

plane_done:
    INC LR10 1 ;;
    ADD LR9 LR9 {{ cr.input_batch }} ; BLT.S LR10 {{ cr.in0_d0 }} plane ;;
    INC LR11 1 ;;
    ADD LR8 LR8 {{ cr.input_plane }} ; BLT.S LR11 {{ cr.in0_d1 }} channel ;;
    HALT ;;
