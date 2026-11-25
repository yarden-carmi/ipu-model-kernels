{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.sizes ~ '.H' %}
{% macro width_part(coef, acc) %}
    MULT.VE LR0 {{ coef }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    # Construct the coefficient 1/sqrt(head width) in the input format.
    {{ width_part('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ width_part(cr.fp_top, 'ADD.FIRST') }} ;;
    {{ width_part(cr.fp_base, 'SUB') }} ;;
    {{ width_part(cr.head_width, 'ADD') }} ; ACTIVATE.QUANTIZE rsqrt {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; DEC LR2 1 ;;

token:
    ADD LR3 LR2 {{ cr.width }} ;;
channel:
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.sizes }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
    ; INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 LR3 channel ;;
    ADD LR1 LR1 {{ cr.gap }} ; DEC LR4 1 ;;
    BNE LR4 CR0 token ;;
    HALT ;;
