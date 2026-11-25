{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro gather() %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD2 LRD4 7
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR9 CR0 ;;
    # Form the runtime head width and broadcast its inverse square root.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;

batch:
    SET LR7 CR0 ; SET LR12 {{ cr.out0_d1 }} ;;
head:
    SET LR8 LR7 ; SET LR11 {{ cr.out0_d2 }} ;;
sequence:
    SET LR6 LR8 ; SET LR10 {{ cr.out0_d3 }} ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; SET LR4 CR0 ; SET LR5 CR0 ; DEC LR10 1 ;;
    BEQ LR10 CR0 last_feature ;;
feature:
    # Gather the current batch lane into the current feature lane.
    {{ gather() }} ; INC LR6 1 ; LD.MULT R0 LR6 {{ cr.in0 }} ; DEC LR10 1 ;;
    ADDBI LRD4 1 ; BNE LR10 CR0 feature ;;
last_feature:
    {{ gather() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ; ADD LR8 LR8 {{ cr.in0_d2 }} ; DEC LR11 1 ;;
    INC LR9 1 ; BNE LR11 CR0 sequence ;;
    ADD LR7 LR7 {{ cr.out0_d3 }} ; DEC LR12 1 ;;
    BNE LR12 CR0 head ;;
    INC LR1 1 ; ADDBI LRD2 1 ;;
    BLT.S LR1 {{ cr.out0_d0 }} batch ;;
    HALT ;;
