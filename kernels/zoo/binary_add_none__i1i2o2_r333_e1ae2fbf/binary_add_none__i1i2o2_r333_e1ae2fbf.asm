{% macro add_store(ds) %}
    LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR14 CR0 ;;
    SET LR7 CR0 ;;
    INC LR14 128 ;;
row:
    // Gather one logical row from column vectors before the vector add.
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
chunk:
    // Pick the gather bound once per chunk, not once per element.
    SET LR13 LR14 ; BLT.S LR14 LR10 gather_setup ;;
    SET LR13 LR10 ;;
gather_setup:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    // Load the first row, then bundle each subsequent load with the index updates.
    LD.MULT R0 LR12 {{ cr.in0 }} ; DEC LR13 1 ;;
    B scatter ;;
gather:
    ADD LR12 LR12 {{ cr.blocks }} ; ADDBI LRD2 1 ; INC LR11 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
scatter:
    MULT.EE LR6 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; BLT.S LR11 LR13 gather ;;
    ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ;;
    BEQ LR10 LR11 tail ;;
    DEC LR10 128 ;;
    {{ add_store('CR15') }}
    B chunk ;;
tail:
    {{ add_store(cr.tail) }}
    BEQ LR5 {{ cr.rows }} done ;;
    INC LR6 1 ; INC LR7 1 ;;
    BEQ LR7 {{ cr.in0_d1 }} batch ;;
    BLT.S LR6 LR14 row ;;
    SET LR6 CR0 ; INC LR9 1 ;;
    B row ;;
batch:
    ADD LR8 LR8 {{ cr.batch_stride }} ; SET LR9 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
    B row ;;
done:
    HALT ;;
