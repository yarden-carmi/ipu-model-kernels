{# Split the reduction at B's physical row boundaries. Within a segment
   R0 stays resident, and the cyclic slot streams A's M-lane rows. #}
{% macro product(first) %}
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR14 ; DEC LR13 1 ; INC LR11 1 ;;
    MULT.RC.VE LR14 LR11 0 LR14 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR9 LR9 {{ cr.m_tiles }}.H ; {{ 'BEQ LR13 CR0 end_segment' if first else 'BNE LR13 CR0 reduce' }} ;;
{% endmacro %}
{% macro segment(caller_id) %}
    SET LR13 CR0 ;;
    INC LR13 128 ;;
    SUB LR13 LR13 LR11 ; LD.MULT R0 LR10 {{ cr.in1 }} ;;
    BLE.S LR13 LR12 segment_ready_{{ caller_id }} ;;
    SET LR13 LR12 ;;
segment_ready_{{ caller_id }}:
    SUB LR12 LR12 LR13 ; DEC LR11 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR7 CR0 ;;
    SET LR14 CR0 ;;
    SET LR15 {{ cr.n_groups }}.H ; DEC LR0 1 ;;
group:
    SET LR2 LR1 ; SET LR3 CR0 ; SET LR4 {{ cr.k_heads }}.H ;;
head:
    SET LR5 LR2 ; SET LR6 {{ cr.n_groups }}.L ;;
column:
    SET LR8 {{ cr.m_tiles }}.H ;;
tile:
    SET LR9 LR7 ; SET LR10 LR5 ; SET LR11 LR3 ;;
    SET LR12 {{ cr.k_heads }}.L ;;
    {{ segment('first') }}
    {{ product(true) }}
reduce:
    {{ product(false) }}
end_segment:
    BEQ LR12 CR0 store ;;
    INC LR10 1 ; SET LR11 CR0 ;;
    {{ segment('later') }}
    B reduce ;;
store:
    DEC LR8 1 ;;
    BEQ LR8 CR0 tail ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR0 1 ; INC LR7 1 ; B tile ;;
tail:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsfull }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ; INC LR0 1 ; DEC LR6 1 ; ADD LR5 LR5 {{ cr.bc }} ;;
    BEQ LR6 CR0 next_head ;;
    SUB LR7 LR7 {{ cr.m_tiles }}.H ;;
    INC LR7 1 ; B column ;;
next_head:
    SUB LR7 LR9 {{ cr.m_tiles }}.H ; DEC LR4 1 ; ADD LR3 LR3 {{ cr.k_heads }}.L ;;
    INC LR7 1 ; SET LR11 CR0 ;;
    INC LR11 128 ;;
normalize:
    BLT.S LR3 LR11 normalized ;;
    SUB LR3 LR3 LR11 ; INC LR2 1 ; B normalize ;;
normalized:
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.b_group }} ; DEC LR15 1 ; ADD LR7 LR7 {{ cr.a_adjust }} ;;
    BNE LR15 CR0 group ;;
    HALT ;;
