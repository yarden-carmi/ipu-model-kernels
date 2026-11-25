{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro row(ds) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR1 1 ; INC LR2 1 ;;
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR5 CR0 ;;
    # Form the attention coefficient from the head width, in both machine modes.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;

batch:
    SET LR1 LR5 ; ADD LR4 LR2 {{ cr.output_batch }} ;;
pair:
    SET LR3 {{ cr.chunks }} ;;
chunk:
    LD.MULT R0 LR1 {{ cr.in0 }} ; DEC LR3 1 ;;
    BEQ LR3 CR0 last_chunk ;;
    {{ row(full) }}
    B chunk ;;
last_chunk:
    {{ row(tail) }}
    BLT.S LR2 LR4 pair ;;
    ADD LR5 LR5 {{ cr.input_batch }} ; DEC LR6 1 ;;
    BNE LR6 CR0 batch ;;
    HALT ;;
