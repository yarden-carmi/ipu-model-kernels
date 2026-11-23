{% macro emit(ds, prefetch=false) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
    ; INC LR4 1
    {% if prefetch %}; INC LR1 1 ; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
{% endmacro %}
{% macro row(ds) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ emit(ds) }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    BEQ CR1 {{ cr.chunks }} single ;;
group:
    SET LR3 CR1 ;;
chunk:
    {{ row(cr.ds_pair ~ '.H') }}
    INC LR1 1 ; INC LR3 1 ;;
    BLT.S LR3 {{ cr.chunks }} chunk ;;
    {{ row(cr.ds_pair ~ '.L') }}
    INC LR1 1 ; INC LR2 1 ;;
    BLT.S LR2 {{ cr.groups }} group ;;
    HALT ;;
single:
    LD.MULT R0 LR1 {{ cr.in0 }} ; BGE.S LR1 {{ cr.last_group }} final_row ;;
stream:
    # Multiply the resident row while fetching its successor. The branch sees
    # the old input pointer, so stop before prefetching past the last row.
    {{ emit(cr.ds_pair ~ '.L', true) }} ; BLT.S LR1 {{ cr.penultimate_group }} stream ;;
final_row:
    {{ emit(cr.ds_pair ~ '.L') }} ; HALT ;;
