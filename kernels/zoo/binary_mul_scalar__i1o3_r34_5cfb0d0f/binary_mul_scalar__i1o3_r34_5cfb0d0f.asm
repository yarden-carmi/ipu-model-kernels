{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro gather(lane) %}
    MULT.RC.VE {{ lane }} LR0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7
{%- endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR4 CR0 ;;
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
batch:
    SET LR6 LR5 ; SET LR7 {{ cr.out0_d1 }} ; SET LR1 CR0 ;;
head:
    SET LR8 CR0 ; SET LR9 LR6 ; SET LR10 {{ cr.out0_d2 }} ;;
sequence:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 LR9 ;;
    SET LR12 {{ cr.out0_d3 }} ; BNE LR1 CR0 odd ;;
even:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; DEC LR12 1 ;;
    {{ gather('LR8') }} ;;
    ADDBI LRD2 1 ; BEQ LR12 CR0 store ;;
odd:
    ADD LR15 LR11 {{ cr.packed_steps }}.H ; BLT.S LR8 LR13 odd_load ;;
    INC LR15 1 ;;
odd_load:
    LD.MULT.CYCLIC LR15 {{ cr.in0 }} LR0 ; DEC LR12 1 ;;
    SET LR15 LR8 ;;
    INC.MODP2 LR15 {{ cr.out0_d2 }} 7 ;;
    {{ gather('LR15') }} ; ADD LR11 LR11 {{ cr.packed_steps }}.L ;;
    ADDBI LRD2 1 ; BNE LR12 CR0 even ;;
store:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; DEC LR10 1 ;;
    INC LR4 1 ;;
    BEQ LR10 CR0 next_head ;;
    INC.MODP2 LR8 CR1 7 ;;
    BNE LR8 CR0 sequence ;;
    INC LR9 1 ; B sequence ;;
next_head:
    DEC LR7 1 ;;
    BEQ LR7 CR0 next_batch ;;
    {# Advance the packed feature cursor by the head width. #}
    SET LR12 {{ cr.out0_d3 }} ;;
advance:
    BEQ LR1 CR0 advance_even ;;
    ADD LR6 LR6 {{ cr.packed_steps }}.L ;;
advance_even:
    INC.MODP2 LR1 CR1 1 ; DEC LR12 1 ;;
    BNE LR12 CR0 advance ;;
    B head ;;
next_batch:
    ADD LR5 LR5 {{ cr.batch_stride }} ; DEC LR14 1 ;;
    BNE LR14 CR0 batch ;;
    HALT ;;
