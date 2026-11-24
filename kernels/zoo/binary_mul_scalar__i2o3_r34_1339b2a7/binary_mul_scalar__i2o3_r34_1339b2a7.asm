{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ; INC LR1 128 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; SET LR10 CR0 ;;

batch:
    SET LR2 LR5 ; SET LR3 CR0 ; SET LR7 {{ cr.out0_d1 }} ;;
head:
    # LR2 and LR3 locate this head's start row and lane in the first sequence position.
    SET LR9 LR2 ; SET LR8 {{ cr.out0_d2 }} ; ADD LR4 LR3 {{ cr.out0_d3 }} ;;
sequence:
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; SET LR11 LR9 ; BLT.S LR4 LR1 store ;;
    BEQ LR4 LR1 store ; INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR1 ;;
store:
    MULT.RC.VE LR3 LR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; DEC LR8 1 ; ADD LR9 LR9 {{ cr.chunks }} ;;
    BNE LR8 CR0 sequence ;;
    DEC LR7 1 ; SET LR3 LR4 ;;
    BEQ LR7 CR0 next_batch ;;
    BLT.S LR3 LR1 head ;;
    DEC LR3 128 ; INC LR2 1 ; B head ;;
next_batch:
    ADD LR5 LR5 {{ cr.batch_stride }} ; DEC LR6 1 ;;
    BNE LR6 CR0 batch ;;
    HALT ;;
