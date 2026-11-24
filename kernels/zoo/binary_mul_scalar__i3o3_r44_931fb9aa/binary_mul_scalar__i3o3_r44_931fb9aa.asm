{% set qi = cr.qf_in0 ~ '.L' %}
{% set full = cr.full_ds ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro scale(index, acc) %}
    MULT.RC.VE {{ index }} LR0 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ;;
    {# Manufacture the 1/8 coefficient in the active format, including FP32. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ; BEQ {{ cr.pairs }} CR0 tail ;;
pair:
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {{ scale('LR0', 'ADD.FIRST') }} ;;
    {{ store(cr.store_ds ~ '.L') }} ;;
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.pairs }} pair ;;
tail:
    BEQ {{ cr.odd }} CR0 done ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    {{ scale('LR0', 'ADD.FIRST') }} ;;
    {{ store(cr.store_ds ~ '.H') }} ;;
done:
    HALT ;;
