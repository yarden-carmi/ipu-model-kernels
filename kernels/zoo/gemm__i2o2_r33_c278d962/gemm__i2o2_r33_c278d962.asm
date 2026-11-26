{% macro load() %}LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1{% endmacro %}
{% macro step(scalar, first=false) %}MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ load() }}{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR8 CR0 ; SET LR10 {{ cr.rows }} ;;
row:
    SET LR4 CR0 ; SET LR6 {{ cr.tiles }} ;;
    DEC LR4 1 ;;
tile:
    SET LR2 LR8 ; {{ load() }} ;;
    {{ step('CR1', first=true) }} ; SET LR9 {{ cr.k }} ;;
    {{ step('CR1') }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SET LR7 LR9 ; SET LR3 CR0 ;;
    BLT.S LR7 LR1 chunk_end ;;
    SET LR7 LR1 ;;
chunk_end:
    SUB LR9 LR9 LR7 ; DEC LR7 1 ; INC LR2 1 ;;
lane:
    {{ step('LR3') }} ; SET LR15 LR3 ;;
    {{ step('LR15') }} ; INC LR3 1 ; BLT.S LR3 LR7 lane ;;
    BNE LR9 CR0 chunk ;;
    DEC LR6 1 ; DEC LR4 1 ;;
    BEQ LR6 CR0 last_tile ;;
    {{ store(cr.full) }}
    B tile ;;
last_tile:
    {{ store(cr.tail) }}
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ;;
    BNE LR10 CR0 row ;;
    HALT ;;
