{# Gather one output row directly in the accumulator, multiplying before scatter.
   For [batch, feature, sequence chunk], adjacent features are chunks rows apart. #}
{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro gather() %}
    MULT.RC.VE LR8 LR0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ; SET LR5 CR0 ; DEC LR4 1 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; SET LR13 CR0 ;;
    INC LR13 128 ;;
batch:
    SET LR6 LR5 ; SET LR7 {{ cr.out0_d1 }} ;;
head:
    SET LR8 CR0 ; SET LR9 LR6 ; SET LR10 {{ cr.out0_d2 }} ;;
sequence:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 LR9 ;;
    SET LR12 {{ cr.out0_d3 }} ; LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; BEQ {{ cr.out0_d3 }} CR1 store ;;
column:
    {{ gather() }} ; LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ; ADD LR11 LR11 {{ cr.chunks }} ; DEC LR12 1 ;;
    ADDBI LRD2 1 ; BNE LR12 CR1 column ;;
store:
    {{ gather() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ; INC LR4 1 ; DEC LR10 1 ;;
    INC LR8 1 ; BEQ LR10 CR0 next_head ;;
    BLT.S LR8 LR13 sequence ;;
    SET LR8 CR0 ; INC LR9 1 ; B sequence ;;
next_head:
    ADD LR6 LR6 LR15 ; DEC LR7 1 ;;
    BNE LR7 CR0 head ;;
    ADD LR5 LR5 {{ cr.batch_stride }} ; DEC LR14 1 ;;
    BNE LR14 CR0 batch ;;
    HALT ;;
