{% macro rhs() %}
    MULT.EE LR5 CR1 0 LR0 {{ cr.scalar_ds }}.L {{ cr.qf_in1 }}.L ; AGG.SUM LR3 {{ cr.scalar_ds }}.L
{% endmacro %}
{% macro store(ds) %}
    {{ rhs() }} ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR6 CR0 ; SET LR7 {{ cr.out0_d1 }} ; SET LR10 CR0 ;;
    INC LR6 128 ;;
block:
    // Each block covers up to 128 source rows and writes one row per column.
    SET LR8 {{ cr.out0_d2 }} ; SET LR9 LR4 ; SET LR2 CR0 ;;
column:
    SET LR11 LR9 ; ADD LR5 LR2 LR6 ; SUB LR3 LR0 CR1 ;;
    SET LR4 LR6 ; LD.MULT R0 LR11 {{ cr.in0 }} ; BGE.S LR7 LR6 gather ;;
    SET LR4 LR7 ;;
gather:
    MULT.EE LR2 CR1 0 LR0 {{ cr.scalar_ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR3 {{ cr.scalar_ds }}.L ; LD.MULT R1 LR11 {{ cr.in1 }} ; INC LR3 1 ; DEC LR4 1 ; BEQ LR4 CR1 write ;;
    {{ rhs() }} ; ADD LR11 LR11 {{ cr.stride0 }} ; LD.MULT R0 LR11 {{ cr.in0 }} ; B gather ;;
write:
    BLT.S LR7 LR6 tail ;;
    {{ store(cr.full_ds ~ '.L') }}
    B advance ;;
tail:
    {{ store(cr.tail_ds ~ '.L') }}
advance:
    INC LR2 1 ; DEC LR8 1 ; BEQ LR8 CR1 next_block ;;
    ADD LR1 LR1 LR14 ;;
    BLT.S LR2 LR6 column ;;
    SET LR2 CR0 ; INC LR9 1 ; B column ;;
next_block:
    BLT.S LR6 LR7 full_block ;;
    INC LR1 1 ;;
    BEQ LR1 LR15 done ;;
    // Recover the block origin from the final column chunk.
    SUB LR4 LR9 {{ cr.stride0 }} ; SET LR7 {{ cr.out0_d1 }} ;;
    ADD LR4 LR4 LR13 ; SET LR10 LR1 ;;
    INC LR4 1 ; B block ;;
full_block:
    SUB LR4 LR9 {{ cr.stride0 }} ; DEC LR7 128 ;;
    ADD LR4 LR4 {{ cr.block0 }} ; INC LR10 1 ;;
    INC LR4 1 ; SET LR1 LR10 ; B block ;;
done:
    HALT ;;
