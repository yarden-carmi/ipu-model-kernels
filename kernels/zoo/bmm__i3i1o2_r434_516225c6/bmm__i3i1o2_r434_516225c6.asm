{# Reuse one RHS K vector across an output column's tile of M rows. #}
{% macro dot_chunk(tag, first, ds) %}
    ADD LR10 LR2 LR9 ; SET LR4 CR0 ; ADD LR11 LR7 LR9 ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
{{ tag }}:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR12 ;;
    MULT.RC.VV LR12 R0 0 LR12 {{ ds }} {{ cr.qf_in0 }}.L ; AGG.SUM{{ '.FIRST' if first else '' }} LR4 {{ ds }} ; ADD LR11 LR11 {{ cr.ak }} ;;
    INC LR4 1 ;;
    BLT.S LR4 LR8 {{ tag }} ;;
    INC LR9 1 ;;
{% endmacro %}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}

    SET LR12 CR0 ; SET LR14 LR15 ;;
head:
    SET LR5 CR0 ;;
column:
    SET LR6 CR0 ; SET LR7 LR1 ;;
tile:
    SET LR8 {{ cr.m }} ; SET LR9 CR0 ; SET LR10 CR0 ;;
    SUB LR8 LR8 LR6 ; INC LR10 128 ;;
    BLE.S LR8 LR10 width_ready ;;
    SET LR8 LR10 ;;
width_ready:
    BLT.S LR9 {{ cr.kcm1 }} first_full ;;
    {{ dot_chunk('first_tail_rows', true, cr.dsk ~ '.L') }}
    B end_k ;;
first_full:
    {{ dot_chunk('first_full_rows', true, cr.ds ~ '.L') }}
    B check_k ;;
next_full:
    {{ dot_chunk('next_full_rows', false, cr.ds ~ '.L') }}
check_k:
    BLT.S LR9 {{ cr.kcm1 }} next_full ;;
    {{ dot_chunk('next_tail_rows', false, cr.dsk ~ '.L') }}
end_k:
    ADD LR6 LR6 LR8 ;;
    BLT.S LR6 {{ cr.m }} full_tile ;;
    {{ store('H') }}
    ADD LR2 LR2 {{ cr.bk }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.n }} column ;;
    ADD LR1 LR1 {{ cr.astride }} ; INC LR3 1 ; DEC LR14 1 ;;
    BGE.S LR3 {{ cr.b }} done ;;
    BNE LR14 CR0 head ;;
    ADD LR2 LR2 LR13 ; SET LR14 LR15 ;;
    B head ;;
full_tile:
    {{ store('L') }}
    SUB LR7 LR11 LR9 ;;
    INC LR7 1 ;;
    B tile ;;
done:
    HALT ;;
