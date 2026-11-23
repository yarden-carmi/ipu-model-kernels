{% set full = cr.ds_pair ~ '.H' %}
{% set partial = cr.ds_pair ~ '.L' %}
{% macro row(ds, prefetch=false, control='') %}
    MULT.VE LR0 {{ cr.fp_top }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR0 {{ cr.fp_base }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.SUB ;;
    MULT.VE LR0 {{ cr.nx_scale }} 0 LR0 {{ ds }} {{ cr.qf_in0 }}.L ; ACC.ADD
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4
    ; INC LR4 1 ; INC LR1 1
    {% if prefetch %}; LD.MULT R0 LR1 {{ cr.in0 }}{% endif %}
    {{ control }} ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR4 CR0 ;;
    DEC LR4 1 ;;
    BEQ {{ cr.lane_remainder }} CR0 dense ;;
group:
    SET LR3 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BEQ LR3 {{ cr.chunks }} tail ;;
chunk:
    {# Branch sees the old chunk index; LOAD sees the advanced input offset. #}
    {{ row(full, true, '; INC LR3 1 ; BLT.S LR3 ' ~ cr.last_chunk ~ ' chunk') }}
tail:
    {{ row(partial, false, '; INC LR2 1 ; BLT.S LR2 ' ~ cr.last_group ~ ' group') }}
    HALT ;;
dense:
    LD.MULT R0 LR1 {{ cr.in0 }} ; BEQ LR1 {{ cr.last_row }} final_row ;;
stream:
    {{ row(full, true, '; BLT.S LR1 ' ~ cr.penultimate_row ~ ' stream') }}
final_row:
    {{ row(full, false, '; HALT') }}
