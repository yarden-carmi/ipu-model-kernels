{% macro load_sum() %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ start_sum() }} ;;
{% endmacro %}
{% macro start_sum() %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }}
{% endmacro %}
{% macro store_sum(ds, offset='LR1') %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} {{ offset }}
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 {{ cr.ra_row }} ; BEQ {{ cr.ic }} CR1 single_plane ;;
plane:
    SET LR3 CR0 ;;
row:
    SET LR4 {{ cr.ic }} ;;
chunk:
    {{ load_sum() }}
    {{ store_sum('CR15.L') }} ; INC LR3 1 ; DEC LR4 1 ;;
    INC LR1 1 ; BNE LR4 CR1 chunk ;;
tail:
    {{ load_sum() }}
    {{ store_sum(cr.tail ~ '.L') }} ; INC LR3 1 ;;
    INC LR1 1 ; BLT.S LR3 {{ cr.plane_rows }} row ;;
    BLT.S LR1 {{ cr.rows }} plane ;;
    HALT ;;

# Keep the next input load in the store word. Peel the final row of
# each plane so the prefetch never reads past the input.
single_plane:
    SET LR3 CR0 ; SUB LR6 LR1 CR1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    BEQ CR1 {{ cr.plane_rows }} single_last ;;
{% macro single_sum(prefetch) %}
    {{ start_sum() }} ; INC LR6 1 ;;
    {{ store_sum(cr.tail ~ '.L', 'LR6') }} ; INC LR1 1 ; INC LR3 1
    {% if prefetch %}
    ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR3 {{ cr.plane_penultimate }} single_row
    {% endif %} ;;
{% endmacro %}
single_row:
    {{ single_sum(true) }}
single_last:
    {{ single_sum(false) }}
    BLT.S LR1 {{ cr.rows }} single_plane ;;
    HALT ;;
