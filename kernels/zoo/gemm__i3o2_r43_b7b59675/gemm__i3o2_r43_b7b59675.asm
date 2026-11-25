{# A segment is the intersection of a logical GEMM row and a physical
   output row. Contributions from different segments occupy disjoint lanes. #}
{% macro load_weight() %}
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ; INC LR6 1
{%- endmacro %}
{% macro mac(scalar, first=false) %}
    MULT.RC.VE LR0 {{ scalar }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{% if first %}.FIRST{% endif %} ; {{ load_weight() }}
{%- endmacro %}
{% macro store(ds) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR7 ; INC LR7 1 ;;
{%- endmacro %}
    SET LR0 CR0 ; SET LR5 CR0 ; SET LR12 CR0 ;;
    SET LR11 {{ cr.out0_d0 }} ; SET LR7 CR0 ;;
    DEC LR7 1 ;;
batch:
    SET LR10 {{ cr.tiles }} ; SET LR8 {{ cr.n }} ; SET LR6 CR0 ;;
tile:
    SET LR9 {{ cr.width }} ; BNE LR10 CR1 init_tile ;;
    SET LR9 {{ cr.tail_count }} ;;
init_tile:
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    B bias_term ;;
segment:
    LD.MULT.CYCLIC LR6 {{ cr.w }} LR0 ;;
bias_term:
    {{ mac('CR1') }} ; SET LR1 LR5 ; SET LR2 LR12 ;;
    {{ mac('CR1') }} ; SET LR4 {{ cr.k }} ;;
input_row:
    LD.MULT R0 LR1 {{ cr.in0 }} ; SET LR3 {{ cr.in0_d3 }} ;;
    SUB LR3 LR3 LR2 ;;
    SET LR13 {{ cr.in0_d3 }} ; BLT.S LR3 LR4 chunk ;;
    ADD LR13 LR2 LR4 ; SET LR3 LR4 ;;
chunk:
    SUB LR4 LR4 LR3 ; DEC LR13 1 ;;
scalar:
    {{ mac('LR2') }} ; SET LR14 LR2 ;;
    {{ mac('LR14') }} ; INC LR2 1 ; BLT.S LR2 LR13 scalar ;;
    BNE LR2 {{ cr.in0_d3 }} input_done ;;
    INC LR1 1 ; SET LR2 CR0 ; BNE LR4 CR0 input_row ;;
input_done:
    BLT.S LR9 LR8 tile_split ;;
    SUB LR9 LR9 LR8 ; SET LR5 LR1 ; SET LR12 LR2 ;;
    SET LR8 {{ cr.n }} ; BNE LR9 CR0 segment ;;
    SET LR6 CR0 ; B tile_end ;;
tile_split:
    SUB LR8 LR8 LR9 ;;
tile_end:
    BEQ LR10 CR1 batch_end ;;
    {{ store(cr.full) }}
    DEC LR10 1 ; B tile ;;
batch_end:
    {{ store(cr.tail) }}
    DEC LR11 1 ; BNE LR11 CR1 batch ;;
    HALT ;;
