{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.ADD.FIRST ;;
    {% for unit in range(4) %}
    MULT.EE LR6 CR1 0 LR0 {{ ds }} {{ qi }} ; ACC.SUB ;;
    {% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ; INC LR4 1 ;;
    INC LR1 1 ; INC LR2 1 ; INC LR3 1 ;;
{% endmacro %}

    // exp2(0) supplies an exact unit to the scalar multiplier.
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.unit }} LR0 ;;
    LD.MULT R1 LR0 {{ cr.unit }} ; INC LR6 128 ; SET LR3 {{ cr.chunks }} ;;
plane_pair:
    SET LR4 CR0 ;;
chunk:
    BEQ LR4 {{ cr.last }} final_chunk ;;
    {{ row(full) }}
    BEQ LR0 CR0 chunk ;;
final_chunk:
    {{ row(tail) }}
    ADD LR2 LR2 {{ cr.chunks }} ; ADD LR3 LR3 {{ cr.chunks }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.pairs }} plane_pair ;;
    HALT ;;
