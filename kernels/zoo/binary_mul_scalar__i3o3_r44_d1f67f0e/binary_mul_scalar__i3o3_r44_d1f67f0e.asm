{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.ds_pair ~ '.H' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro load_pair() %}
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0
{%- endmacro %}
{% macro store_item(start) %}
    MULT.RC.VE {{ start }} LR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; INC LR2 1
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds_pair }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 {{ cr.pair_count }} ;;
    # Generate 1/8 in the input format, in both FP32 and NX8 modes.
    {{ coefficient('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ coefficient(cr.fp_hi, 'ADD.FIRST') }} ;;
    {{ coefficient(cr.fp_lo, 'SUB') }} ;;
    {{ coefficient(cr.nx_scale, 'ADD') }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; BEQ LR4 CR0 tail ;;
pair:
    {{ load_pair() }} ;;
    {{ store_item('LR0') }} ;;
    {{ store_item('LR3') }} ; INC LR1 1 ; DEC LR4 1 ; BLT.S CR1 LR4 pair ;;
tail:
    BEQ {{ cr.odd }} CR0 done ;;
    {{ load_pair() }} ;;
    {{ store_item('LR0') }} ;;
done:
    HALT ;;
