{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
    # Seed a vector of ones, then materialize the scalar in the input format.
    {{ coefficient('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ coefficient(cr.fp_hi, 'ADD.FIRST') }}
    {{ coefficient(cr.fp_lo, 'SUB') }}
    {{ coefficient(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR1 {{ cr.last }} final ;;
stream:
    # Branch sees the old index; the store and prefetch see the incremented offsets.
    {{ row(cr.valid) }} ; INC LR1 1 ; INC LR2 1 ; LD.MULT R0 LR1 {{ cr.in0 }}
    ; BLT.S LR1 {{ cr.penultimate }} stream ;;
final:
    {{ row(cr.tail) }} ; INC LR2 1 ; HALT ;;
