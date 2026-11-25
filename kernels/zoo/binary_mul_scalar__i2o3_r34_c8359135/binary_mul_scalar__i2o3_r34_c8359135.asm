{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro carry(row, lane, ready) %}
    BLT.S {{ lane }} LR1 {{ ready }} ;;
    DEC {{ lane }} 128 ; INC {{ row }} 1 ;;
{%- endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    # Form 1/sqrt(head width) and quantize it in the input format.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ; INC LR1 128 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; SET LR10 CR0 ;;

batch:
    SET LR2 LR5 ; SET LR3 CR0 ; SET LR7 {{ cr.out0_d1 }} ;;
head:
    # Keep the head origin separate from the cursor through packed sequence items.
    SET LR9 LR2 ; SET LR12 LR3 ; SET LR8 {{ cr.out0_d2 }} ;;
sequence:
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR0 ; ADD LR4 LR12 {{ cr.out0_d3 }} ; SET LR11 LR9 ;;
    BLT.S LR4 LR1 store ;;
    BEQ LR4 LR1 store ; INC LR11 1 ;;
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR1 ;;
store:
    MULT.RC.VE LR12 LR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ tail }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; DEC LR8 1 ; ADD LR9 LR9 {{ cr.seq_rows }} ;;
    BEQ LR8 CR0 next_head ; ADD LR12 LR12 LR13 ;;
    {{ carry('LR9', 'LR12', 'sequence') }}
    B sequence ;;
next_head:
    DEC LR7 1 ; ADD LR3 LR3 {{ cr.out0_d3 }} ;;
    BEQ LR7 CR0 next_batch ;;
    {{ carry('LR2', 'LR3', 'head') }}
    B head ;;
next_batch:
    ADD LR5 LR5 {{ cr.batch_stride }} ; DEC LR6 1 ;;
    BNE LR6 CR0 batch ;;
    HALT ;;
