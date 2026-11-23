{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
    INC LR6 1 ; SET LR5 CR0 ;;
{% endmacro %}
{% set padded = (in0_d1 * in0_d2) % 128 != 0 %}

    SET LR0 CR0 ; SET LR3 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR12 CR0 ; SET LR13 CR1 ;;
    INC LR12 128 ; INC LR13 255 ;;
batch:
    SET LR7 CR0 ; SET LR9 LR8 ; SET LR5 CR0 ;;
logical_row:
    // in0's logical (i,j,k) starts at flat storage offset i + d0*j.
    SET LR1 CR0 ; SET LR2 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
    {% if padded %}
    // Keep an unpadded offset alongside the physical address.
    SET LR11 LR9 ; BLT.S LR9 LR14 start_split ;;
start_batch_wrap:
    SUB LR11 LR11 LR14 ; ADD LR1 LR1 LR15 ;;
    BGE.S LR11 LR14 start_batch_wrap ;;
start_split:
    SET LR2 LR11 ;;
    {% endif %}
    SET LR4 LR12 ; BLT.S LR2 LR12 element ;;
split_start:
    INC LR1 1 ; DEC LR2 128 ;;
    BGE.S LR2 LR12 split_start ;;
element:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    LD.MULT R1 LR3 {{ cr.in1 }} ; MULT.EE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR5 {{ cr.one }}.L ;;
    MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; AGG.SUM LR5 {{ cr.one }}.L ; ADD LR1 LR1 {{ cr.stride_rows }} ; DEC LR10 1{% if (in0_d0 * in0_d1) % 128 %} ; INC LR2 {{ (in0_d0 * in0_d1) % 128 }}{% endif %} ;;
    INC LR5 1 ; INC LR4 1 ; BLT.S LR2 LR12 a_ready ;;
    INC LR1 1 ; DEC LR2 128 ;;
a_ready:
    {% if padded %}
    ADD LR11 LR11 {{ cr.view_stride }} ;;
    BLT.S LR11 LR14 b_check ;;
advance_batch:
    SUB LR11 LR11 LR14 ; INC LR2 {{ 128 - (in0_d1 * in0_d2) % 128 }} ;;
    BLT.S LR2 LR12 batch_carry_done ;;
    INC LR1 1 ; DEC LR2 128 ;;
batch_carry_done:
    BGE.S LR11 LR14 advance_batch ;;
b_check:
    {% endif %}
    BLT.S LR4 LR13 b_ready ;;
    INC LR3 1 ; SET LR4 LR12 ;;
b_ready:
    BNE LR5 LR12 row_check ;;
    {{ store('CR15') }}
row_check:
    BNE LR10 CR0 element ;;
    BEQ LR4 LR12 next_row ;;
    INC LR3 1 ;;
next_row:
    INC LR7 1 ; ADD LR9 LR9 {{ cr.in0_d0 }} ;;
    BNE LR7 {{ cr.in0_d1 }} logical_row ;;
    BEQ LR5 CR0 next_batch ;;
    {{ store(cr.tail) }}
next_batch:
    INC LR8 1 ;;
    BNE LR8 {{ cr.in0_d0 }} batch ;;
    HALT ;;
