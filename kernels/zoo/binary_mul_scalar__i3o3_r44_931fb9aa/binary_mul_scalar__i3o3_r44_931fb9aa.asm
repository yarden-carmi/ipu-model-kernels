{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro row(width) %}
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ width }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
    # Generate 1/8 in the input format in both FP32 and NX8 modes.
    {{ coefficient('CR0', 'ADD.FIRST') }} ; ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ coefficient(cr.fp_hi, 'ADD.FIRST') }} ;;
    {{ coefficient(cr.fp_lo, 'SUB') }} ;;
    {{ coefficient(cr.nx_scale, 'ADD') }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; BEQ {{ cr.pairs }} CR0 tail ;;
pair:
    {{ row(cr.widths ~ '.L') }} ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.pairs }} pair ;;
tail:
    BEQ {{ cr.odd }} CR0 done ;;
    {{ row(cr.widths ~ '.H') }} ;;
done:
    HALT ;;
