{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

// Iterate in in1's physical order: (batch, x, y-block).
// LR4:LR5 is the padded row base and logical column at y=0.
batch:
    SET LR4 CR0 ; SET LR5 LR13 ; SET LR15 {{ cr.x_cols_count }}.L ;;
    BLT.S LR5 {{ cr.col_limit }}.L x_loop ;;
batch_wrap:
    SUB LR5 LR5 {{ cr.col_limit }}.L ; ADD LR4 LR4 LR11 ;;
    BGE.S LR5 {{ cr.col_limit }}.L batch_wrap ;;
x_loop:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.width_batch }}.L ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR14 CR0 ;;
    SET LR10 {{ cr.tail }}.H ; BNE LR12 CR1 full_count ;;
    BEQ LR0 CR0 gather ;;
full_count:
    SET LR10 {{ cr.col_limit }}.H ;;
gather:
    SET LR8 LR6 ; SET LR9 LR7 ; BLT.S LR7 {{ cr.col_limit }}.H first_row ;;
lane_wrap:
    INC LR8 1 ; SUB LR9 LR9 {{ cr.col_limit }}.H ;;
    BGE.S LR9 {{ cr.col_limit }}.H lane_wrap ;;
first_row:
    LD.MULT R0 LR8 {{ cr.in0 }} ;
    ADD LR6 LR6 {{ cr.stride_rows }} ; ADD LR7 LR7 {{ cr.stride_cols }} ; INC LR14 1 ;;
    MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD2 0 ; BLT.S LR7 {{ cr.col_limit }}.L no_wrap ;;
    SUB LR7 LR7 {{ cr.col_limit }}.L ; ADD LR6 LR6 LR11 ;;
no_wrap:
    ADDBI LRD2 1 ; BLT.S LR14 LR10 gather ;;
    LD.MULT R0 LR1 {{ cr.in1 }} ; BNE LR12 CR1 full_store ;;
    {{ add_store(cr.tail ~ '.L') }}
    BEQ LR0 CR0 stored ;;
full_store:
    {{ add_store('CR15.L') }}
stored:
    INC LR1 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 chunk ;;
    ADD LR4 LR4 {{ cr.x_rows }} ; ADD LR5 LR5 {{ cr.x_cols_count }}.H ; DEC LR15 1 ;;
    BLT.S LR5 {{ cr.col_limit }}.L x_next ;;
    SUB LR5 LR5 {{ cr.col_limit }}.L ; ADD LR4 LR4 LR11 ;;
x_next:
    BNE LR15 CR0 x_loop ;;
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.width_batch }}.H batch ;;
    HALT ;;
