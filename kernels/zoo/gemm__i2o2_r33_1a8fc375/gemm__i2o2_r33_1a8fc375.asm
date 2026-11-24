{% macro load() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
# The MAC reads the old cyclic row while the load replaces it for the next MAC.
{% macro step(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ load() }}{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR11 CR0 ;;
    SET LR10 {{ cr.rows }} ; SET LR12 {{ cr.in0_d1 }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR11 ; {{ load() }} ;;
    {% set bias_scalar = 'CR1' if bias else 'CR0' %}
    {{ step(bias_scalar, first=true) }} ; SET LR9 {{ cr.k }} ;;
    {{ step(bias_scalar) }} ;;
    {{ step(bias_scalar) }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR3 LR9 ;;
    BLT.S LR7 LR1 chunk_end ;;
    SET LR7 LR1 ;;
chunk_end:
    SUB LR13 LR7 LR3 ; SET LR14 LR7 ;;
    SUB LR9 LR9 LR13 ; DEC LR14 1 ;;
loop_lane:
    {{ step('LR3') }} ;;
    {{ step('LR3') }} ; SET LR15 LR3 ;;
    # Compare the old lane and advance it; the MAC uses the saved index.
    {{ step('LR15') }} ; INC LR3 1 ; BLT.S LR3 LR14 loop_lane ;;
    BNE LR3 LR1 partial ;;
    INC LR2 1 ; SET LR3 CR0 ;;
partial:
    BNE LR9 CR0 chunk ;;
    # The final MAC prefetched the next tile's first plane (or the guard row).
    DEC LR6 1 ; DEC LR4 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    DEC LR10 1 ; DEC LR12 1 ;;
    BEQ LR10 CR0 done ;;
    SET LR8 LR2 ; SET LR11 LR3 ;;
    BNE LR12 CR0 row ;;
    SET LR12 {{ cr.in0_d1 }} ;;
    BEQ LR11 CR0 row ;;
    INC LR8 1 ; SET LR11 CR0 ; B row ;;
done:
    HALT ;;
