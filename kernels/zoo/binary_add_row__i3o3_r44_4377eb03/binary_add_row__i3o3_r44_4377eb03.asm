{% macro load_sum(advance=false) %}
    LD.MULT R0 LR1 {{ cr.in0 }}{% if advance %} ; INC LR1 1{% endif %} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R1 LR3 {{ cr.operand }}{% if advance %} ; INC LR3 1{% endif %} ;;
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

# A one-chunk row always uses the tail mask. Loads see the incremented
# offsets; the store and loop branch both use the resulting row indices.
single_plane:
    SET LR6 {{ cr.plane_rows }} ; SET LR7 {{ cr.rows }} ; DEC LR1 1 ;;
    DEC LR6 1 ; DEC LR7 1 ;;
single_plane_next:
    SET LR3 CR0 ;;
    DEC LR3 1 ;;
single_row:
    {{ load_sum(true) }}
    {{ store_sum(cr.tail ~ '.L') }} ; BLT.S LR3 LR6 single_row ;;
    BLT.S LR1 LR7 single_plane_next ;;
    HALT ;;
