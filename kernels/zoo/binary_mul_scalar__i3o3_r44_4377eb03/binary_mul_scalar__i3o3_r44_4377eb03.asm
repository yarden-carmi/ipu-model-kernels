{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR0 {{ coefficient }} 0 LR0 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro row(ds, prefetch=false, control='') %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
    ; INC LR4 1 ; INC LR1 1
    {% if prefetch %}; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
    {{ control }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    {# Synthesize 1/8 once, then keep the broadcast row resident in RC. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT R0 LR0 {{ cr.scalar }} ;;
    {{ product(cr.fp_top, 'ADD.FIRST') }}
    {{ product(cr.fp_base, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; BEQ {{ cr.last }} {{ cr.full_lanes }} start_dense ;;
group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR6 CR0 tail_row ;;
chunk:
    {{ row(full, true, '; INC LR3 1 ; BLT.S LR3 LR6 chunk') }}
tail_row:
    {{ row(tail, false, '; INC LR2 1 ; BLT.S LR2 LR7 group') }}
    HALT ;;
start_dense:
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR1 {{ cr.last_row }} final_row ;;
dense:
    {# Branch uses the old input index; the load uses the incremented one. #}
    {{ row(full, true, '; BLT.S LR1 LR5 dense') }}
final_row:
    {{ row(full, false, '; HALT') }}
