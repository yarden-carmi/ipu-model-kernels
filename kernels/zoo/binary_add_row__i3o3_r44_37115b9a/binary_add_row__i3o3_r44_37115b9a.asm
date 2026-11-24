{% macro load_sum() %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ;;
{% endmacro %}
{% macro pipelined_row(prefetch) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }} ; INC LR8 1 ; INC LR1 1 ;;
    {{ store_sum(cr.tail ~ '.L') }}{% if prefetch %} ; LD.MULT R0 LR8 {{ cr.in0 }} ; INC LR3 1 ; BLT.S LR3 LR9 single_row{% endif %} ;;
{% endmacro %}
{% macro store_sum(ds) %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    INC LR2 128 ; SET LR5 CR0 ;;
    INC LR5 1 ;;
    BEQ {{ cr.ic }} LR5 single_plane ;;
plane:
    SET LR3 CR0 ;;
row:
    SET LR4 {{ cr.ic }} ;;
chunk:
    {{ load_sum() }}
    {{ store_sum('CR15.L') }} ; INC LR3 1 ; DEC LR4 1 ;;
    INC LR1 1 ; BNE LR4 LR5 chunk ;;
tail:
    {{ load_sum() }}
    {{ store_sum(cr.tail ~ '.L') }} ; INC LR3 1 ;;
    INC LR1 1 ; BLT.S LR3 {{ cr.plane_rows }} row ;;
    BLT.S LR1 {{ cr.rows }} plane ;;
    HALT ;;

# A one-chunk physical row can contain several logical rows. The tail mask
# counts their combined width. Peel the last physical row to bound prefetch.
single_plane:
    SET LR6 {{ cr.plane_rows }} ; SET LR7 {{ cr.rows }} ; SET LR8 CR0 ;;
    DEC LR1 1 ; SET LR9 {{ cr.plane_rows }} ;;
    DEC LR6 1 ; DEC LR7 1 ;;
    DEC LR9 2 ;;
single_plane_next:
    SET LR3 CR0 ; LD.MULT R0 LR8 {{ cr.in0 }} ; BEQ LR6 LR0 single_last ;;
single_row:
    {{ pipelined_row(true) }}
single_last:
    {{ pipelined_row(false) }}
    BLT.S LR1 LR7 single_plane_next ;;
    HALT ;;
