{% set qi = cr.qf_in0 ~ '.L' %}
{% set one = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ one }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    # Generate 1/sqrt(head width) once, in lane zero of R0.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ one }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ one }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;

batch:
    SET LR3 CR0 ; SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR5 LR3 ; SET LR6 {{ cr.out0_d2 }} ;;
token:
    SET LR7 LR5 ; SET LR8 CR0 ;;
feature:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR1 LR0 0 LR0 {{ one }} {{ qi }} ; AGG.SUM.FIRST LR8 {{ one }} ; INC LR7 1 ;;
    INC LR8 1 ;;
    BLT.S LR8 {{ cr.out0_d3 }} feature ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; ADD LR5 LR5 {{ cr.in0_d2 }} ; DEC LR6 1 ;;
    BNE LR6 CR0 token ;;
    ADD LR3 LR3 {{ cr.out0_d3 }} ; DEC LR4 1 ;;
    BNE LR4 CR0 head ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.out0_d0 }} batch ;;
    HALT ;;
