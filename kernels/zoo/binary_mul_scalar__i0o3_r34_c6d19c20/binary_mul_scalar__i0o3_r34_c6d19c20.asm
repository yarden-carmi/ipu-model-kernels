{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    # Materialize the attention scale 1/sqrt(head width).
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; SET LR11 CR0 ;;

batch:
    SET LR3 CR0 ; SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR5 LR3 ; SET LR6 {{ cr.out0_d2 }} ;;
sequence:
    SET LR7 LR5 ; SET LR8 {{ cr.out0_d3 }} ; SET LR13 CR0 ;;
    # The batch index selects a lane; each feature is a separate input row.
feature:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.RC.VE LR0 LR1 0 LR0 {{ full }} {{ qi }} ; ACC.RESHAPE LRD10 LRD12 7 ; INC LR7 1 ; DEC LR8 1 ;;
    ADDBI LRD12 1 ; BNE LR8 CR0 feature ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; ADD LR5 LR5 {{ cr.in0_d2 }} ; DEC LR6 1 ;;
    INC LR2 1 ; BNE LR6 CR0 sequence ;;
    ADD LR3 LR3 {{ cr.out0_d3 }} ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.out0_d0 }} batch ;;
    HALT ;;
