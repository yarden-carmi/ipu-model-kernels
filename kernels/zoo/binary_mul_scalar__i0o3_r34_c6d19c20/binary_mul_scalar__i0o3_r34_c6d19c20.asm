{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro scatter() %}
    MULT.RC.VE LR8 LR0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD0 LRD2 7
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR8 CR0 ;;
    # Form the head width before quantization, then take its inverse square root.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; SET LR9 CR0 ;;

batch:
    SET LR4 CR0 ; SET LR10 {{ cr.out0_d1 }} ;;
head:
    SET LR5 LR4 ; SET LR11 {{ cr.out0_d2 }} ;;
sequence:
    SET LR6 LR5 ; SET LR7 {{ cr.out0_d3 }} ; SET LR2 CR0 ;;
    SET LR3 CR0 ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ; BEQ LR7 CR1 last_lane ;;
gather:
    INC LR6 1 ; DEC LR7 1 ; {{ scatter() }} ; LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    ADDBI LRD2 1 ; BNE LR7 CR1 gather ;;
last_lane:
    {{ scatter() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; DEC LR11 1 ; ADD LR5 LR5 {{ cr.in0_d2 }} ;;
    BNE LR11 CR0 sequence ;;
    ADD LR4 LR4 {{ cr.out0_d3 }} ; DEC LR10 1 ;;
    BNE LR10 CR0 head ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.out0_d0 }} batch ;;
    HALT ;;
