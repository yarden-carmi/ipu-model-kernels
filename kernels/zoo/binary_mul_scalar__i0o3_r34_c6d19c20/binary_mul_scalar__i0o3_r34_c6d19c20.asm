{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
    SET LR0 CR0 ; DEC LR1 1 ; SET LR2 CR0 ;;
    # Synthesize the attention scale from the head width.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ; SET LR3 CR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;

batch:
    SET LR4 CR0 ; SET LR5 {{ cr.out0_d1 }} ;;
head:
    SET LR6 LR4 ; SET LR7 {{ cr.out0_d2 }} ;;
    DEC LR6 1 ;;
token:
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 {{ cr.out0_d3 }} ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR6 1 ; SUB LR9 LR9 {{ cr.lane_step }} ; DEC LR10 1 ; BEQ LR10 CR1 last_column ;;
column:
    LD.MULT R0 LR6 {{ cr.in0 }} ; MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD2 LRD8 7 ; INC LR6 1 ; DEC LR10 1 ; ADD LR9 LR9 {{ cr.lane_step }} ; BLT.S CR1 LR10 column ;;
last_column:
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD2 LRD8 7 ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR1 1 ; ADD LR9 LR9 {{ cr.lane_step }} ; ADD LR6 LR6 {{ cr.token_skip }} ;;
    DEC LR7 1 ; BNE LR7 CR1 token ;;
    ADD LR4 LR4 {{ cr.out0_d3 }} ; DEC LR5 1 ; BNE LR5 CR1 head ;;
    ADDBI LRD2 1 ; DEC LR15 1 ; BNE LR15 CR1 batch ;;
    HALT ;;
