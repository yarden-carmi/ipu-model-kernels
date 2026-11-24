{% macro add_input(operand_step=false) %}
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }}{% if operand_step %} ; INC LR3 1{% endif %}
{% endmacro %}
{% macro load_sum() %}
    LD.MULT R0 LR1 {{ cr.in0 }} ;;
    {{ add_input() }} ;;
{% endmacro %}
{% macro store_sum(ds, offset='LR1') %}
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} {{ offset }}
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

# A one-chunk physical row (possibly multiple logical rows) uses the tail mask. The store word loads the next
# input into R0, while the input multiply word loads the current operand.
single_plane:
    SET LR6 {{ cr.plane_rows }} ;;
    DEC LR6 2 ;;
single_plane_next:
    SET LR3 CR0 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
    DEC LR3 1 ; BEQ {{ cr.plane_rows }} LR5 single_last ;;
single_row:
    {{ add_input(true) }} ; SET LR8 LR1 ; INC LR1 1 ;;
    {{ store_sum(cr.tail ~ '.L', 'LR8') }} ; LD.MULT R0 LR1 {{ cr.in0 }} ; BLT.S LR3 LR6 single_row ;;
single_last:
    {{ add_input(true) }} ;;
    {{ store_sum(cr.tail ~ '.L') }} ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.rows }} single_plane_next ;;
    HALT ;;
