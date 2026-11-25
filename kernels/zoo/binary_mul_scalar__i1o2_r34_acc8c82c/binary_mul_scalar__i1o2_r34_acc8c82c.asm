{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full_ds ~ '.L' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro row(ds) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}
    SET LR0 CR0 ; SET LR2 CR0 ; SET LR5 CR0 ;;
    # Synthesize 1, then use it to form the head width for rsqrt.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ; DEC LR2 1 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;

batch:
    SET LR1 LR5 ; ADD LR7 LR2 {{ cr.output_batch }} ;;
group:
    # Stream the whole batch if masks are uniform; otherwise stop at each feature tail.
    ADD LR4 LR2 {{ cr.run_limit }} ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BLT.S LR4 LR2 last_row ;;
stream:
    {{ row(cr.ds_pair ~ '.H') }} ; INC LR1 1 ; INC LR2 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR2 LR4 stream ;;
last_row:
    {{ row(tail) }} ; INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 LR7 group ;;
    ADD LR5 LR5 {{ cr.input_batch }} ; DEC LR6 1 ;;
    BNE LR6 CR0 batch ;;
    HALT ;;
