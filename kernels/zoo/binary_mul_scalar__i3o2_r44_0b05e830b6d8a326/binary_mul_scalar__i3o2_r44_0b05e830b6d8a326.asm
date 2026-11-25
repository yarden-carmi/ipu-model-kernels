{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coef, acc) %}
    MULT.VE LR14 {{ coef }} 0 LR14 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
{% endmacro %}
{% macro scatter(advance=false, prefetch=false) %}
    MULT.RC.VE LR14 LR11 0 LR14 {{ full }} {{ qi }} ; ACC.RESHAPE LRD12 LRD12 7
    {% if advance %}; ADDBI LRD12 1{% endif %}
    {% if prefetch %}; ADD LR4 LR4 {{ cr.ic }} ; LD.MULT R0 LR4 {{ cr.in0 }}{% endif %}
{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}

    SET LR14 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    // Materialize the scalar in the input format and keep it in R_CYCLIC.
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.scalar }} ;;
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT.CYCLIC LR14 {{ cr.scalar }} LR14 ;;
batch:
    SET LR0 CR0 ;;
channel:
    SET LR3 LR2 ; SET LR10 LR1 ; SET LR11 CR0 ;;
column:
    SET LR4 LR10 ; SET LR7 CR0 ;;
tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR6 CR1 ;;
    INC LR7 1 ;;
    BEQ LR7 {{ cr.oc }} partial_count ;;
    SET LR6 CR0 ;;
    INC LR6 128 ; B gather ;;
partial_count:
    SET LR6 LR15 ;;
gather:
    LD.MULT R0 LR4 {{ cr.in0 }} ; BEQ LR6 CR1 singleton ;;
    // Multiply while gathering down dimension 2. Load one row ahead.
    {{ scatter(prefetch=true) }} ; DEC LR6 2 ;;
    BEQ LR6 CR0 final_lane ;;
next_lane:
    {{ scatter(advance=true, prefetch=true) }} ; DEC LR6 1 ; BLT.S CR1 LR6 next_lane ;;
final_lane:
    {{ scatter(advance=true) }} ; B tile_done ;;
singleton:
    {{ scatter() }} ;;
tile_done:
    ADD LR4 LR4 {{ cr.ic }} ; BEQ LR7 {{ cr.oc }} final_tile ;;
    {{ store(full) }}
    B tile ;;
final_tile:
    {{ store(tail) }}
    SUB LR3 LR3 {{ cr.oc }} ;;
    ADD LR3 LR3 {{ cr.column_stride }} ; INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 same_chunk ;;
    INC LR10 1 ;;
same_chunk:
    SUB LR6 LR3 LR5 ;;
    BLT.S LR6 LR2 column ;;
    ADD LR1 LR1 {{ cr.plane_rows }} ; INC LR0 1 ;;
    BEQ LR0 {{ cr.out0_d1 }} next_batch ;;
    ADD LR2 LR2 {{ cr.oc }} ; B channel ;;
next_batch:
    ADD LR2 LR2 LR8 ;;
    BLT.S LR1 LR9 batch ;;
    HALT ;;
