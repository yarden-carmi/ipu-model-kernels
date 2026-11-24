{# Exact scalar dots: both operands stay in their original rows and scales. #}
{% macro product(first) -%}
    MULT.RC.VE LR11 LR11 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM{% if first %}.FIRST{% endif %} LR12 {{ cr.ds }}.L ; INC LR11 1 ; DEC LR9 1 ;
{%- endmacro %}
group:
    SET LR1 CR0 ; SET LR13 CR0 ; SET LR5 {{ cr.head_config }}.L ;;
head:
    SET LR15 {{ cr.mn }}.L ; ADD LR14 LR3 LR13 ;;
output_row:
    ADD LR2 LR4 LR13 ; SET LR12 CR0 ;;
column:
    BNE LR1 CR0 scalar_column ;;
    BLT.S {{ cr.width }} {{ cr.k }} scalar_column ;;
    LD.MULT R0 LR14 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR2 {{ cr.in1 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR12 {{ cr.head_config }}.H ; B column_done ;;
scalar_column:
    SET LR8 {{ cr.k }} ; SET LR10 LR2 ; SET LR11 LR1 ;;
feature_row:
    SUB LR9 LR10 LR2 ;;
    ADD LR9 LR9 LR14 ;;
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR0 ;;
    SET LR9 {{ cr.width }} ;;
    SUB LR9 LR9 LR11 ;;
    BLT.S LR9 LR8 chunk_ready ;;
    SET LR9 LR8 ;;
chunk_ready:
    SUB LR8 LR8 LR9 ; DEC LR11 1 ;;
    BNE LR10 LR2 chunk_loop ;;
    {{ product(true) }} BEQ LR9 CR1 chunk_done ;;
chunk_loop:
    {{ product(false) }} BNE LR9 CR1 chunk_loop ;;
chunk_done:
    BEQ LR8 CR0 column_done ;;
    SET LR11 CR0 ; INC LR10 1 ; B feature_row ;;
column_done:
    ADD LR2 LR2 {{ cr.strides }}.H ; INC LR12 1 ;;
    BEQ LR12 {{ cr.mn }}.H second_row ;;
    SET LR9 {{ cr.mn }}.H ;;
    ADD LR9 LR9 {{ cr.mn }}.H ;;
    BLT.S LR12 LR9 column ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; DEC LR15 2 ;;
    INC LR7 1 ; BEQ LR15 CR0 head_done ;;
    ADD LR14 LR14 {{ cr.strides }}.L ; B output_row ;;
second_row:
    ADD LR14 LR14 {{ cr.strides }}.L ; ADD LR2 LR4 LR13 ; B column ;;
head_done:
    DEC LR5 1 ; ADD LR1 LR1 {{ cr.k }} ;;
    BEQ LR5 CR0 group_done ;;
head_normalize:
    BLT.S LR1 {{ cr.width }} head ;;
    DEC LR1 128 ; INC LR13 1 ; B head_normalize ;;
group_done:
    ADD LR3 LR3 {{ cr.agroup }} ; ADD LR4 LR4 {{ cr.bgroup }} ; DEC LR6 1 ;;
    BNE LR6 CR0 group ;;
    HALT ;;
