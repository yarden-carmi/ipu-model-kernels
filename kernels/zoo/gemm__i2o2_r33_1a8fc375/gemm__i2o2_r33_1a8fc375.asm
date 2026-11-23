{% macro load(slot) %}LD.MULT.CYCLIC LR4 {{ cr.w }} {{ slot }} ; INC LR4 1{% endmacro %}
{% macro mac(slot, scalar, first=false) %}MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro dot(scalar, first=false) %}
    {{ load('LR0') }} ;;
    {{ mac('LR0', scalar, first) }} ; {{ load('LR1') }} ;;
    {{ mac('LR1', scalar) }} ; {{ load('LR0') }} ;;
    {{ mac('LR0', scalar) }} ;;
{% endmacro %}
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
    SET LR2 LR8 ; SET LR3 LR11 ; SET LR9 {{ cr.k }} ;;
    {{ dot('CR1' if bias else 'CR0', first=true) }}
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; ADD LR7 LR3 LR9 ;;
    BLT.S LR7 LR1 chunk_end ;;
    SET LR7 LR1 ;;
chunk_end:
    SUB LR13 LR7 LR3 ;;
    SUB LR9 LR9 LR13 ;;
loop_lane:
    {{ dot('LR3') }}
    INC LR3 1 ;;
    BLT.S LR3 LR7 loop_lane ;;
    BNE LR3 LR1 partial ;;
    INC LR2 1 ; SET LR3 CR0 ;;
partial:
    BNE LR9 CR0 chunk ;;
    DEC LR6 1 ;;
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
