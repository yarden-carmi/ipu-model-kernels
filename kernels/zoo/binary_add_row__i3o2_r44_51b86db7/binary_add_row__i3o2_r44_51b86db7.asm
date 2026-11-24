{% macro add_store(ds) %}
    LD.MULT R0 LR10 {{ cr.operand }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_operand }}.L ; ACC.ADD ; INC LR10 1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    INC LR11 1 ;;
{% endmacro %}

{% macro gather_lane() %}
    MULT.EE LR6 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 {{ cr.planes }} ; SET LR11 CR0 ; SET LR14 CR0 ;;
    SET LR15 CR0 ; INC LR14 128 ;;
    INC LR15 1 ;;
plane:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR10 CR0 ;;
column:
    ADD LR9 LR4 LR8 ; SET LR12 {{ cr.in0_d2 }} ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR13 LR12 ;
    LD.MULT R0 LR9 {{ cr.in0 }} ; BLT.S LR12 LR14 chunk_count ;;
    SET LR13 LR14 ;;
chunk_count:
    SUB LR12 LR12 LR13 ; BEQ LR13 LR15 last_lane ;;
    # Peel the first lane to start the reshape destination at zero.
    {{ gather_lane() }} ; ADD LR9 LR9 {{ cr.ic }} ; DEC LR13 2 ; LD.MULT R0 LR9 {{ cr.in0 }} ;;
    BEQ LR13 CR0 advance_last ;;
gather:
    {{ gather_lane() }} ; ADDBI LRD2 1 ; ADD LR9 LR9 {{ cr.ic }} ; DEC LR13 1 ; LD.MULT R0 LR9 {{ cr.in0 }} ; BLT.S LR15 LR13 gather ;;
advance_last:
    ADDBI LRD2 1 ;;
last_lane:
    # Drain without loading beyond the last input row.
    {{ gather_lane() }} ; ADD LR9 LR9 {{ cr.ic }} ; BEQ LR12 CR0 tail ;;
    {{ add_store('CR15.L') }}
    B chunk ;;
tail:
    {{ add_store(cr.tail ~ '.L') }}
    INC LR7 1 ; INC LR6 1 ;;
    BEQ LR7 {{ cr.in0_d3 }} next_plane ;;
    BLT.S LR6 LR14 column ;;
    SET LR6 CR0 ; INC LR8 1 ; B column ;;
next_plane:
    ADD LR4 LR4 {{ cr.plane_rows }} ; DEC LR5 1 ;;
    BNE LR5 CR0 plane ;;
    HALT ;;
