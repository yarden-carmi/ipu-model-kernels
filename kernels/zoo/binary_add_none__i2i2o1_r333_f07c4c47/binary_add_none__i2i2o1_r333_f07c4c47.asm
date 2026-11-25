{% set full = cr.masks ~ '.H' %}
{% macro clear() %}
    MULT.VE LR15 CR0 0 LR15 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST
{% endmacro %}
{% macro make_basis(zero_slot, unit_slot, qf) %}
    {{ clear() }} ; ACTIVATE.QUANTIZE identity {{ full }} {{ qf }}.L {{ cr.basis }} LR15 ;;
    LD.MULT.CYCLIC LR15 {{ cr.basis }} {{ zero_slot }} ;;
    ACTIVATE.QUANTIZE exp2 {{ cr.unit_ds }}.L {{ qf }}.L {{ cr.basis }} LR15 ;;
    LD.MULT.CYCLIC LR15 {{ cr.basis }} {{ unit_slot }} ;;
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6 ;;
{% endmacro %}

    SET LR15 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
    SET LR13 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    INC LR13 128 ; INC LR4 255 ; INC LR5 255 ;;
    INC LR4 129 ; INC LR5 1 ;;
    // Two format-specific one-hot vectors in the cyclic multiplier ring.
    {{ make_basis('LR4', 'LR15', cr.qf_in0) }}
    {{ make_basis('LR13', 'LR5', cr.qf_in1) }}
batch:
    SET LR9 {{ cr.in0_d2 }} ; SET LR8 LR7 ; SET LR0 CR0 ;;
column:
    SET LR12 LR8 ; SET LR10 {{ cr.in0_d1 }} ;;
chunk:
    SET LR4 CR0 ; SET LR14 LR5 ; SET LR11 LR13 ;;
    BGE.S LR10 LR13 gather_setup ;;
    SET LR11 LR10 ;;
gather_setup:
    {{ clear() }} ;;
gather:
    // Broadcast the selected column and route it to the destination lane.
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.RC.VE LR4 LR0 0 LR15 {{ full }} {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR12 {{ cr.in1 }} ;;
    MULT.RC.VE LR14 LR0 0 LR15 {{ full }} {{ cr.qf_in1 }}.L ; ACC.ADD ; ADD LR12 LR12 {{ cr.stride }} ; DEC LR4 1 ; DEC LR11 1 ;;
    DEC LR14 1 ; BNE LR11 CR0 gather ;;
    BLT.S LR13 LR10 store_full ;;
    {{ store(cr.masks ~ '.L') }}
    INC LR6 1 ; DEC LR9 1 ; INC LR0 1 ;;
    BEQ LR6 {{ cr.output_rows }} done ;;
    BEQ LR9 CR0 next_batch ;;
    BLT.S LR0 LR13 column ;;
    SET LR0 CR0 ; INC LR8 1 ; B column ;;
store_full:
    {{ store(full) }}
    INC LR6 1 ; DEC LR10 128 ; B chunk ;;
next_batch:
    ADD LR7 LR7 {{ cr.batch_rows }} ; B batch ;;
done:
    HALT ;;
