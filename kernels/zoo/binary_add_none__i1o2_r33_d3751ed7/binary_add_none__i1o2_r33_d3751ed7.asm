{% set full = cr.ds_pair ~ '.H' %}
{% macro scatter() %}
    MULT.EE LR6 CR1 0 LR0 {{ full }} {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7
{%- endmacro %}
{% macro add_store(ds) %}
    MULT.VE LR0 CR1 0 LR0 {{ ds }} {{ cr.qf_operand }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}

    // Gather one output vector at a time without intermediate quantization.
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR14 CR0 ;;
    INC LR14 128 ;;
row:
    ADD LR12 LR8 LR9 ; SET LR10 {{ cr.in0_d2 }} ;;
chunk:
    SET LR13 LR14 ; BLT.S LR14 LR10 bound ;;
    SET LR13 LR10 ;;
bound:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR11 CR0 ;;
    SUB LR10 LR10 LR13 ; DEC LR13 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    BEQ LR13 CR0 last ;;
    {{ scatter() }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ;;
    DEC LR13 1 ;;
    BLT.S LR13 LR11 advance_last ;;
gather:
    {{ scatter() }} ; ADD LR12 LR12 {{ cr.blocks }} ; INC LR11 1 ; ADDBI LRD2 1 ; LD.MULT R0 LR12 {{ cr.in0 }} ; BLT.S LR11 LR13 gather ;;
advance_last:
    ADDBI LRD2 1 ;;
last:
    {{ scatter() }} ; ADD LR12 LR12 {{ cr.blocks }} ; LD.MULT R0 LR5 {{ cr.operand }} ;;
    BEQ LR10 CR0 tail ;;
    {{ add_store(full) }}
    B chunk ;;
tail:
    {{ add_store(cr.ds_pair ~ '.L') }}
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
