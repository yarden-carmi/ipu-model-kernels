{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

// Traverse (d1,d0) groups in storage-offset order for the strided view.
// LR4:LR5 is the padded row base and column of each group's first element.
y_loop:
    SET LR1 LR13 ; SET LR15 {{ cr.width_batch }}.H ;;
batch:
    SET LR6 LR4 ; SET LR7 LR5 ; SET LR12 {{ cr.width_batch }}.L ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR14 CR0 ;;
    SET LR10 CR0 ; BNE LR12 CR1 full_count ;;
    SET LR10 {{ cr.tail }}.H ; BEQ LR0 CR0 gather ;;
full_count:
    INC LR10 128 ;;
gather:
    SET LR8 LR6 ; SET LR9 LR7 ; BLT.S LR7 {{ cr.col_limit }}.H first_row ;;
lane_wrap:
    INC LR8 1 ; SUB LR9 LR9 {{ cr.col_limit }}.H ;;
    BGE.S LR9 {{ cr.col_limit }}.H lane_wrap ;;
first_row:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
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
    INC LR5 1 ; ADD LR1 LR1 {{ cr.jump }} ; DEC LR15 1 ;;
    BLT.S LR5 {{ cr.col_limit }}.L batch_next ;;
    SET LR5 CR0 ; ADD LR4 LR4 LR11 ;;
batch_next:
    BNE LR15 CR0 batch ;;
    ADD LR13 LR13 {{ cr.width_batch }}.L ;;
    BLT.S LR13 {{ cr.batch_rows }} y_loop ;;
    HALT ;;
