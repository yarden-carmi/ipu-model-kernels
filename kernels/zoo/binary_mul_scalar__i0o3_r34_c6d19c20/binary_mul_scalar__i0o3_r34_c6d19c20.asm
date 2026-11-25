{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR4 CR0 ; SET LR11 CR0 ; SET LR6 {{ cr.out0_d0 }} ;;
    # Build the head width in the accumulator, then apply rsqrt before
    # quantization so the width itself is never rounded to NX8.
    {{ coefficient('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    SET LR9 {{ cr.out0_d3 }} ; {{ coefficient('CR0', 'ADD.FIRST') }} ;;
width:
    {{ coefficient('CR1', 'ADD') }} ; DEC LR9 1 ; BLT.S CR1 LR9 width ;;
    ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;

batch:
    SET LR10 CR0 ; SET LR7 {{ cr.out0_d1 }} ;;
head:
    SET LR8 {{ cr.out0_d2 }} ; SET LR13 LR10 ;;
sequence:
    # The first physical row is s * in0_d2 + h * out0_d3.
    # Within it, lane b belongs to this batch. The source lane stays fixed
    # while each successive physical row contributes one output lane.
    SET LR1 LR13 ; SET LR5 CR0 ; SET LR9 {{ cr.out0_d3 }} ; {{ coefficient('CR0', 'ADD.FIRST') }} ;;
gather:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 7 ; DEC LR9 1 ; INC LR1 1 ;;
    ADD LR5 LR5 {{ cr.index_step }} ; BLT.S CR0 LR9 gather ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ; ADD LR13 LR13 LR12 ; DEC LR8 1 ; BLT.S CR1 LR8 sequence ;;
    ADD LR10 LR10 {{ cr.out0_d3 }} ; DEC LR7 1 ; BLT.S CR1 LR7 head ;;
    ADD LR3 LR3 {{ cr.index_step }} ; DEC LR6 1 ; BLT.S CR1 LR6 batch ;;
    HALT ;;
