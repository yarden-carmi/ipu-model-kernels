{% set full = cr.ds_pair ~ '.H' %}
{% set tail = cr.ds_pair ~ '.L' %}
{% set qi = cr.qf_in0 ~ '.L' %}
{% macro product(coefficient, acc) %}
    MULT.VE LR14 {{ coefficient }} 0 LR14 {{ full }} {{ qi }} ; ACC.{{ acc }} ;;
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
    SET LR14 CR0 ; SET LR0 CR0 ; SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    {# Synthesize a broadcast coefficient in both arithmetic modes. #}
    {{ product('CR0', 'ADD.FIRST') }}
    ACTIVATE.QUANTIZE exp2 {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT R0 LR14 {{ cr.scalar }} ;;
    {{ product(cr.fp_hi, 'ADD.FIRST') }}
    {{ product(cr.fp_lo, 'SUB') }}
    {{ product(cr.nx_scale, 'ADD') }}
    ACTIVATE.QUANTIZE identity {{ full }} {{ qi }} {{ cr.scalar }} LR14 ;;
    LD.MULT.CYCLIC LR14 {{ cr.scalar }} LR14 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
    SET LR10 LR4 ; SET LR11 LR5 ; SET LR12 LR6 ;;
    SET LR13 LR7 ;;
    SET LR6 CR1 ;;
    INC LR6 1 ;;
    BNE {{ cr.oc }} LR6 plane ;;
    BNE LR15 LR9 plane ;;
    BEQ LR8 {{ cr.h }} staged ;;
    B fast_plane ;;
plane:
    SET LR2 CR0 ; SET LR10 LR1 ; SET LR11 CR0 ;;
row:
    SET LR4 LR10 ; SET LR7 CR0 ;;
tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR6 CR1 ;;
    SET LR8 LR9 ; INC LR7 1 ;;
    BNE LR7 {{ cr.oc }} gather ;;
    SET LR8 LR15 ;;
gather:
    LD.MULT R0 LR4 {{ cr.in0 }} ; BEQ LR8 CR1 singleton ;;
    {# Each input column supplies one lane of the output row. #}
    {{ scatter(prefetch=true) }} ; INC LR6 2 ;;
    BLT.S LR8 LR6 finish_gather ;;
gather_next:
    {{ scatter(advance=true, prefetch=true) }} ; INC LR6 1 ; BLT.S LR6 LR8 gather_next ;;
finish_gather:
    {{ scatter(advance=true) }} ; B gathered ;;
singleton:
    {{ scatter() }} ;;
gathered:
    ADD LR4 LR4 {{ cr.ic }} ; BEQ LR7 {{ cr.oc }} tail_store ;;
    {{ store(full) }}
    B tile ;;
tail_store:
    {{ store(tail) }}
    INC LR2 1 ; INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 same_chunk ;;
    INC LR10 1 ;;
same_chunk:
    BLT.S LR2 {{ cr.h }} row ;;
    ADD LR1 LR1 {{ cr.plane_rows }} ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.planes }} plane ;;
    HALT ;;

{# Two full output tiles: avoid the per-tile tail and singleton tests. #}
{% macro fast_tile(n) %}
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR6 CR1 ;;
    INC LR6 2 ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {{ scatter(prefetch=true) }} ;;
fast_gather_{{ n }}:
    {{ scatter(advance=true, prefetch=true) }} ; INC LR6 1 ; BLT.S LR6 LR9 fast_gather_{{ n }} ;;
    {{ scatter(advance=true) }} ; ADD LR4 LR4 {{ cr.ic }} ;;
    {{ store(full) }}
{% endmacro %}
fast_plane:
    SET LR2 CR0 ; SET LR10 LR1 ; SET LR11 CR0 ;;
fast_row:
    SET LR4 LR10 ;;
    {% for n in range(2) %}{{ fast_tile(n) }}{% endfor %}
    INC LR2 1 ; INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 fast_same_chunk ;;
    INC LR10 1 ;;
fast_same_chunk:
    BLT.S LR2 {{ cr.h }} fast_row ;;
    ADD LR1 LR1 {{ cr.plane_rows }} ; INC LR0 1 ;;
    BLT.S LR0 {{ cr.planes }} fast_plane ;;
    HALT ;;

{% macro stage_cell(advance, prefetch) %}
    MULT.RC.VV LR14 R0 0 LR14 {{ full }} {{ qi }} ; ACC.RESHAPE LRD6 LRD8 0
    {% if advance %}; ADDBI LRD8 1{% endif %}
    {% if prefetch %}; ADD LR4 LR4 {{ cr.ic }} ; LD.MULT R0 LR4 {{ cr.in0 }}{% endif %} ;;
{% endmacro %}
{% macro stage_group() %}
    ADD LR4 LR0 LR2 ; SET LR8 LR12 ; SET LR9 LR13 ;;
    ADD LR4 LR4 LR1 ;;
    MULT.VE LR14 CR0 0 LR14 {{ full }} {{ qi }} ; ACC.ADD.FIRST ; LD.MULT R0 LR4 {{ cr.in0 }} ;;
    {% for k in range(8) %}{{ stage_cell(k > 0, k < 7) }}{% endfor %}
    ACTIVATE.QUANTIZE identity {{ full }} {{ cr.qf_out0 }}.L {{ cr.scalar }} LR5 ; ADDBI LRD6 8 ;;
    INC LR5 1 ;;
{% endmacro %}
{% macro gather_cell(advance, prefetch) %}
    MULT.VE LR14 CR1 0 LR14 {{ full }} {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD6 LRD8 0
    {% if advance %}; ADDBI LRD8 8{% endif %}
    {% if prefetch %}; LD.MULT R0 LR4 {{ cr.scalar }} ; INC LR4 16{% endif %} ;;
{% endmacro %}
{% macro gather_tile() %}
    SET LR8 LR10 ; SET LR9 LR11 ; LD.MULT R0 LR4 {{ cr.scalar }} ;;
    {% for k in range(16) %}{{ gather_cell(k > 0, k < 15) }}{% endfor %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ full }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR4 16 ;;
    INC LR5 1 ;;
{% endmacro %}
staged:
    SET LR0 CR0 ; SET LR15 CR0 ; SET LR5 CR1 ;;
stage_plane:
    SET LR1 CR0 ;;
stage_chunk:
    SET LR2 CR0 ;;
stage_columns:
    SET LR6 LR10 ; SET LR7 LR11 ;;
    {% for g in range(16) %}{{ stage_group() }}{% endfor %}
    {% for k in range(8) %}ADD LR2 LR2 {{ cr.ic }} ;;{% endfor %}
    BLT.S LR2 {{ cr.plane_rows }} stage_columns ;;
    INC LR1 1 ;;
    BLT.S LR1 {{ cr.ic }} stage_chunk ;;
    ADD LR0 LR0 {{ cr.plane_rows }} ; INC LR15 1 ;;
    BLT.S LR15 {{ cr.planes }} stage_plane ;;

    SET LR0 CR1 ; SET LR1 CR1 ; SET LR5 CR0 ;;
    SET LR15 CR0 ; SET LR13 CR0 ;;
    INC LR13 8 ;;
output_plane:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR12 CR0 ;;
    SET LR6 LR10 ; SET LR7 LR11 ;;
output_row:
    SET LR4 LR1 ;;
    {% for tile in range(2) %}{{ gather_tile() }}{% endfor %}
    INC LR2 1 ; INC LR3 1 ; ADDBI LRD6 8 ;;
    BNE LR3 LR13 output_continue ;;
    SET LR3 CR0 ; INC LR1 1 ; INC LR12 1 ;;
    SET LR6 LR10 ; SET LR7 LR11 ; SET LR4 LR13 ;;
    ADD LR4 LR4 LR13 ;;
    BNE LR12 LR4 output_continue ;;
    SET LR12 CR0 ; INC LR0 128 ;;
    INC LR0 128 ;;
    INC LR0 128 ;;
    INC LR0 128 ;;
    SET LR1 LR0 ;;
output_continue:
    BLT.S LR2 {{ cr.h }} output_row ;;
    INC LR15 1 ;;
    BLT.S LR15 {{ cr.planes }} output_plane ;;
    HALT ;;
