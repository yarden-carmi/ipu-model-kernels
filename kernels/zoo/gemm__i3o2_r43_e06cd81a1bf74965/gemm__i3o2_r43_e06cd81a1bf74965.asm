{# Stream one weight row ahead. Each R0 load supplies all
   reduction lanes of one head chunk; the last lane never reads padding. #}
{% macro load(slot) %}LD.MULT.CYCLIC LR6 {{ cr.w }} {{ slot }} ; INC LR6 1{% endmacro %}
{% macro mult(slot, scalar, first=false) %}MULT.RC.VE {{ slot }} {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %}{% endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ; DEC LR9 1 ; BNE LR9 CR1 tile ;;
{% endmacro %}
    SET LR0 CR0 ; SET LR10 CR0 ; SET LR8 {{ cr.rows }} ;;
    SET LR13 CR0 ; SET LR14 CR0 ; SET LR7 CR0 ;;
    DEC LR13 1 ; DEC LR14 1 ; DEC LR7 1 ;;
    SET LR5 {{ cr.last_lane }} ;;
row:
    SET LR6 CR0 ; SET LR9 {{ cr.tiles }} ;;
    DEC LR6 1 ;;
tile:
    SET LR2 LR10 ; SET LR3 LR14 ; {{ load('LR0') }} ;;
{% set b = 'CR1' if bias else 'CR0' %}
    {{ mult('LR0', b, true) }} ; {{ load('LR0') }} ; SET LR11 {{ cr.k }} ;;
chunk:
    LD.MULT R0 LR2 {{ cr.in0 }} ; SUB LR12 LR5 LR3 ;;
    ADD LR4 LR3 LR11 ; BGE.S LR12 LR11 final_chunk ;;
    SET LR4 {{ cr.last_lane }} ; SUB LR11 LR11 LR12 ; B start_chunk ;;
final_chunk:
    SET LR11 CR0 ;;
start_chunk:
    DEC LR4 1 ;;
    DEC LR4 1 ; BEQ LR4 LR3 last_lane ;;
lane:
    {{ mult('LR0', 'LR3') }} ; {{ load('LR0') }} ; INC LR3 1 ; BNE LR3 LR4 lane ;;
last_lane:
    {{ mult('LR0', 'LR3') }} ; INC LR3 1 ; BEQ LR11 CR0 store_tile ;;
    INC LR2 1 ; SET LR3 LR13 ;;
    {{ load('LR0') }} ; B chunk ;;
store_tile:
    BEQ LR9 CR1 last_tile ;;
    {{ store(cr.full) }}
last_tile:
    {{ store(cr.tail) }}
    BNE LR3 {{ cr.last_lane }} next_row ;;
    INC LR2 1 ; SET LR3 LR13 ;;
next_row:
    SET LR10 LR2 ; SET LR14 LR3 ; DEC LR8 1 ; BNE LR8 CR1 row ;;
    HALT ;;
