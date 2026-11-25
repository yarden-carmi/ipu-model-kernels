{% macro load() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
# Stream coefficient planes against the gathered input scalar.
{% macro step(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ load() }}{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR11 CR0 ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.rows }} ;;
    SET LR12 CR0 ; SET LR13 {{ cr.in0_d1 }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR11 ; {{ load() }} ;;
    {% set bias_scalar = 'CR1' if bias else 'CR0' %}
    {{ step(bias_scalar, first=true) }} ; SET LR9 {{ cr.k }} ;;
    {{ step(bias_scalar) }} ;;
    {{ step(bias_scalar) }} ;;
feature:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    {{ step('LR3') }} ;;
    {{ step('LR3') }} ; DEC LR9 1 ; SET LR15 LR3 ;;
    {{ step('LR15') }} ; ADD LR3 LR3 {{ cr.pitch_lanes }} ; ADD LR2 LR2 {{ cr.pitch_rows }} ; BEQ LR9 CR0 tile_end ;;
    # Advancing one feature means advancing in0_d1 logical storage elements.
    BLT.S LR3 {{ cr.in0_d2 }} feature ;;
    SUB LR3 LR3 {{ cr.in0_d2 }} ; INC LR2 1 ; B feature ;;
tile_end:
    DEC LR6 1 ; DEC LR4 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    DEC LR10 1 ; INC LR11 1 ; DEC LR13 1 ; BEQ LR10 CR1 done ;;
    BEQ LR13 CR0 next_batch ;;
    BLT.S LR11 {{ cr.in0_d2 }} row ;;
    SET LR11 CR0 ; INC LR8 1 ; B row ;;
next_batch:
    ADD LR12 LR12 {{ cr.in0_d1 }} ; SET LR13 {{ cr.in0_d1 }} ; SET LR11 CR0 ;;
    SET LR8 LR12 ; B row ;;
done:
    HALT ;;
