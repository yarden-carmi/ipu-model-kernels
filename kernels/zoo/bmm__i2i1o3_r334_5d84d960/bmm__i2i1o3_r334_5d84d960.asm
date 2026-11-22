// Stream RHS vectors across N, broadcasting A scalars from a resident row.
{% macro product(first) %}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR14 ; DEC LR13 1 ; INC LR11 1 ;;
    MULT.RC.VE LR14 LR11 0 LR14 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR9 LR9 {{ cr.bc }} ; {{ 'BEQ LR13 CR0 end_segment' if first else 'BNE LR13 CR0 reduce' }} ;;
{% endmacro %}
{% macro segment(id) %}
    SET LR13 CR0 ;;
    INC LR13 128 ;;
    SUB LR13 LR13 LR11 ; LD.MULT R0 LR10 {{ cr.in0 }} ;;
    BLE.S LR13 LR12 segment_ready_{{ id }} ;;
    SET LR13 LR12 ;;
segment_ready_{{ id }}:
    SUB LR12 LR12 LR13 ; DEC LR11 1 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsfull }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR14 CR0 ; SET LR15 {{ cr.m_groups }}.H ;;
group:
    SET LR2 LR1 ; SET LR3 CR0 ; SET LR4 {{ cr.k_heads }}.H ;;
head:
    SET LR5 LR2 ; SET LR6 {{ cr.m_groups }}.L ;;
row:
    SET LR8 {{ cr.tiles }} ;;
tile:
    SET LR9 LR7 ; SET LR10 LR5 ; SET LR11 LR3 ;;
    SET LR12 {{ cr.k_heads }}.L ;;
    {{ segment('first') }}
    {{ product(true) }}
reduce:
    {{ product(false) }}
end_segment:
    BEQ LR12 CR0 output ;;
    INC LR10 1 ; SET LR11 CR0 ;;
    {{ segment('later') }}
    B reduce ;;
output:
    DEC LR8 1 ;;
    BEQ LR8 CR0 tail ;;
    {{ store('L') }}
    INC LR0 1 ; INC LR7 1 ; B tile ;;
tail:
    {{ store('H') }}
    INC LR0 1 ; DEC LR6 1 ; ADD LR5 LR5 {{ cr.ac }} ;;
    BEQ LR6 CR0 next_head ;;
    SUB LR7 LR7 {{ cr.tiles }} ;;
    INC LR7 1 ; B row ;;
next_head:
    SUB LR7 LR9 {{ cr.tiles }} ; DEC LR4 1 ; ADD LR3 LR3 {{ cr.k_heads }}.L ;;
    INC LR7 1 ; SET LR11 CR0 ;;
    INC LR11 128 ;;
normalize:
    BLT.S LR3 LR11 normalized ;;
    SUB LR3 LR3 LR11 ; INC LR2 1 ; B normalize ;;
normalized:
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.a_group }} ; ADD LR7 LR7 {{ cr.b_gap }} ; DEC LR15 1 ;;
    BNE LR15 CR0 group ;;
    HALT ;;
