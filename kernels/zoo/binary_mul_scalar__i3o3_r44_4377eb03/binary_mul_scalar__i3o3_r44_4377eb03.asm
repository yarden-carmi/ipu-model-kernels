{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds, prefetch, control) %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
    ; INC LR4 1 ; INC LR1 1
    {% if prefetch %}; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
    {{ control }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    {# Build the scalar once and retain it while streaming input rows. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; BEQ LR15 CR0 dense ;;
group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BEQ LR3 {{ cr.chunks }} partial ;;
chunk:
    {{ row(full, true, '; INC LR3 1 ; BLT.S LR3 ' ~ cr.last_chunk ~ ' chunk') }}
partial:
    {{ row(tail, false, '; INC LR2 1 ; BLT.S LR2 ' ~ cr.last_group ~ ' group') }}
    HALT ;;
dense:
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR1 {{ cr.last_row }} final_row ;;
stream:
    {{ row(full, true, '; BLT.S LR1 ' ~ cr.penultimate_row ~ ' stream') }}
final_row:
    {{ row(full, false, '; HALT') }}
