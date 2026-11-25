{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full ~ '.L' %}
{% macro coefficient(value, acc) %}
    MULT.VE LR0 {{ value }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro product(window, acc) %}
    MULT.RC.VV {{ window }} R0 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    # Materialize 1/8 in the input format (also works in FP32).
    {{ coefficient('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ coefficient(cr.fp_hi, 'ADD.FIRST') }}
    {{ coefficient(cr.fp_lo, 'SUB') }}
    {{ coefficient(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;

group:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    {{ product('LR0', 'ADD.FIRST') }} ; INC LR1 1 ; BEQ {{ cr.pack }} CR1 write ;;
    BEQ LR1 {{ cr.irows }} write ;;
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR4 ;;
    # The shifted window begins in zero padding and places the second
    # row's first element immediately after the first row's last element.
    {{ product('LR3', 'ADD') }} ; INC LR1 1 ;;
write:
    BEQ LR2 {{ cr.last }} final ;;
    {{ store(cr.valid) }} ;;
    INC LR2 1 ; BEQ CR0 CR0 group ;;
final:
    {{ store(cr.tail) }} ; HALT ;;
