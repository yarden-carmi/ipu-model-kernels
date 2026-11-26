{% macro load() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
{% macro step(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ load() }}{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR11 CR0 ; SET LR5 CR0 ;;
    SET LR8 CR0 ; SET LR10 {{ cr.m }} ; SET LR13 {{ cr.in0_d1 }} ;;
    SET LR1 CR0 ; SET LR7 LR12 ;;
    INC LR1 128 ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; SET LR3 LR11 ; {{ load() }} ;;
    {{ step('CR1', true) }} ; SET LR9 {{ cr.k }} ;;
    {{ step('CR1') }} ;;
    {{ step('CR1') }} ;;
feature:
    BLT.S LR3 LR1 low_chunk ;;
    SET LR15 LR2 ;;
    INC LR15 1 ;;
    LD.MULT R1 LR15 {{ cr.in0 }} ; B mac ;;
low_chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
mac:
    {{ step('LR3') }} ;;
    {{ step('LR3') }} ; DEC LR9 1 ; SET LR15 LR3 ;;
    {{ step('LR15') }} ; ADD LR3 LR3 {{ cr.pitch_lanes }} ; ADD LR2 LR2 {{ cr.pitch_rows }} ; BEQ LR9 CR0 tile_end ;;
    BLT.S LR3 {{ cr.in0_d2 }} feature ;;
    SUB LR3 LR3 {{ cr.in0_d2 }} ; ADD LR2 LR2 LR14 ; B feature ;;
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
    SET LR11 CR0 ; ADD LR8 LR8 LR14 ; B row ;;
next_batch:
    SET LR8 LR12 ; ADD LR12 LR12 LR7 ; SET LR13 {{ cr.in0_d1 }} ;;
    SET LR11 CR0 ; B row ;;
done:
    HALT ;;
