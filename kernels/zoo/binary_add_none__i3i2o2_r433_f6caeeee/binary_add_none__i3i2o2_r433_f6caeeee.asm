{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
{% endmacro %}

    SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
phase:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 LR5 ;;
position:
    SET LR9 LR7 ; SET LR10 LR15 ;;
chunk:
    SET LR3 CR0 ; SET LR11 {{ cr.full_end }} ;;
    BNE LR10 CR1 gather ;;
    SET LR11 {{ cr.tail_end }} ;;
gather:
    // Every channel has the same spatial lane, one pitch farther in memory.
    LD.MULT R0 LR9 {{ cr.in0 }} ;;
    MULT.EE LR8 CR1 0 LR0 {{ cr.full_ds }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADD LR9 LR9 {{ cr.pitch }} ; ADD LR3 LR3 LR14 ;;
    BNE LR3 LR11 gather ;;

    LD.MULT R0 LR4 {{ cr.in1 }} ;;
    BEQ LR10 CR1 last_chunk ;;
    {{ add_store(cr.full_ds ~ '.L') }}
    INC LR4 1 ; DEC LR10 1 ; B chunk ;;
last_chunk:
    {{ add_store(cr.tail_ds ~ '.L') }}
    INC LR4 1 ; INC LR6 1 ; ADD LR8 LR8 {{ cr.out0_d0 }} ;;
    BGE.S LR6 {{ cr.out0_d1 }} next_phase ;;
    BLT.S LR8 {{ cr.packed_width }} position ;;
    SUB LR8 LR8 {{ cr.packed_width }} ; INC LR7 1 ; B position ;;
next_phase:
    INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d0 }} phase ;;
    HALT ;;
