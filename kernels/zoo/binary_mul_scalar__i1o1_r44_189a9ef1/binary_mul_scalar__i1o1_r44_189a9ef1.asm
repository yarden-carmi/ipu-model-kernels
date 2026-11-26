{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro row(ds, prefetch=false, control='') %}
    MULT.RC.VV LR0 R0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2
    ; INC LR2 1
    {% if prefetch %}; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
    {{ control }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    DEC LR2 1 ;;
    # Generate unity in the operand format before loading the cyclic vector.
    MULT.VE LR0 CR0 0 LR0 {{ full }} {{ qi }} ; ACC.ADD.FIRST ;;
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR0 ;;
    LD.MULT.CYCLIC LR0 {{ cr.scalar }} LR0 ; BEQ {{ cr.mixed_width }} CR0 dense ;;
group:
    SET LR3 CR0 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
chunk:
    {{ row(full, true, '; INC LR3 1') }}
    BLT.S LR3 {{ cr.last_chunk }} chunk ;;
group_tail:
    {{ row(tail, false, '; INC LR1 1 ; BLT.S LR1 ' ~ cr.last_row ~ ' group') }}
    HALT ;;
dense:
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR1 {{ cr.last_row }} final ;;
stream:
    {{ row(tail, true, '; BLT.S LR1 ' ~ cr.penultimate ~ ' stream') }}
final:
    {{ row(tail, false, '; HALT') }}
