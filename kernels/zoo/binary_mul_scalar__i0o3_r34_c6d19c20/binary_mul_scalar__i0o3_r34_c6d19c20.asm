{% set qi = cr.qf_in0 ~ '.L' %}
{% set ds = cr.tail ~ '.L' %}
{% macro gather() %}
    MULT.EE LR0 CR1 0 LR15 {{ ds }} {{ qi }} ; ACC.RESHAPE LRD14 LRD2 7
{% endmacro %}
    SET LR0 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    SET LR4 CR0 ; INC LR12 128 ;;
    # Generate the attention scale from the head width in the active format.
    MULT.VE LR15 CR0 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE exp2 {{ ds }} {{ qi }} CR0 LR13 ;;
    LD.MULT R0 LR13 CR0 ;;
    MULT.VE LR15 {{ cr.fp_top }} 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
    MULT.VE LR15 {{ cr.fp_base }} 0 LR15 {{ ds }} {{ qi }} ; ACC.SUB ;;
    MULT.VE LR15 {{ cr.head_width }} 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD ; ACTIVATE.QUANTIZE rsqrt {{ ds }} {{ qi }} CR0 LR13 ;;
    LD.MULT R1 LR13 CR0 ;;
batch:
    SET LR5 CR0 ; SET LR6 CR0 ;;
head:
    SET LR7 LR6 ; SET LR8 {{ cr.out0_d2 }} ;;
sequence:
    SET LR9 LR7 ; SET LR10 {{ cr.out0_d3 }} ; SET LR2 CR0 ;;
    SET LR3 CR0 ;;
column:
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    {{ gather() }} ; BEQ LR10 CR1 drain ;;
    INC LR9 1 ; DEC LR10 1 ; ADDBI LRD2 1 ; B column ;;
drain:
    ACTIVATE.QUANTIZE identity {{ ds }} {{ qi }} {{ cr.gathered }} LR15 ;;
    LD.MULT.CYCLIC LR15 {{ cr.gathered }} LR15 ;;
    MULT.RC.VE LR15 LR12 0 LR15 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; ADD LR7 LR7 {{ cr.in0_d2 }} ; DEC LR8 1 ;;
    BNE LR8 CR0 sequence ;;
    ADD LR6 LR6 {{ cr.out0_d3 }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d1 }} head ;;
    INC LR0 1 ;;
    BLT.S LR0 {{ cr.out0_d0 }} batch ;;
    HALT ;;
