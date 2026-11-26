{% macro row(ds, advance_chunk) %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.ds_pair }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST
    ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 {% if advance_chunk %}; INC LR2 1 {% endif %};;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ;;
group:
    SET LR2 CR0 ; BEQ {{ cr.last_chunk }} CR0 tail ;;
full:
    {{ row(cr.ds_pair ~ '.H', true) }}
    BLT.S LR2 {{ cr.last_chunk }} full ;;
tail:
    {{ row(cr.ds_pair ~ '.L', false) }}
    BLE.S LR1 {{ cr.last_row }} group ;;
    HALT ;;
