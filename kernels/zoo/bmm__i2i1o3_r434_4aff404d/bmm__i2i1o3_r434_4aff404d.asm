{# Gather one query into K lanes, then reduce against each packed RHS
   column directly into the corresponding output lane. #}
{% macro store(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.width }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR14 ;;
    INC LR14 1 ;;
{% endmacro %}

group:
    SET LR15 {{ cr.out0_d1 }} ; SET LR8 LR2 ; SET LR9 CR0 ;;
head:
    SET LR5 LR4 ; SET LR6 CR0 ; SET LR7 {{ cr.m }} ;;
query:
    SET LR3 CR0 ; SET LR13 LR5 ; SET LR12 {{ cr.kwidth }}.L ;;
gather:
    LD.MULT R0 LR13 {{ cr.in0 }} ;;
    MULT.EE LR6 CR1 0 LR2 {{ cr.width }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADD LR3 LR3 LR0 ; ADD LR13 LR13 {{ cr.strides }}.L ; DEC LR12 1 ; BNE LR12 CR1 gather ;;
    ACTIVATE.QUANTIZE identity {{ cr.kwidth }}.H {{ cr.qf_in0 }}.L {{ cr.query }} LR12 ;;
    LD.MULT R0 LR12 {{ cr.query }} ; SET LR10 LR8 ; SET LR11 LR9 ;;
    SET LR12 {{ cr.n }} ;;
tile:
    SET LR13 CR0 ;;
column:
    SET LR3 CR0 ;;
    LD.MULT.CYCLIC LR10 {{ cr.in1 }} LR3 ;;
    MULT.RC.VV LR11 R0 0 LR3 {{ cr.width }}.L {{ cr.qf_in1 }}.L ; AGG.SUM.FIRST LR13 {{ cr.kwidth }}.H ;;
    BEQ LR11 CR0 even_done ;;
    SET LR11 CR0 ; INC LR10 1 ; B advance ;;
even_done:
    SET LR11 {{ cr.kwidth }}.L ;;
advance:
    DEC LR12 1 ; BEQ LR12 CR1 row_done ; INC.MODP2 LR13 CR1 7 ;;
    BNE LR13 CR0 column ;;
    {{ store('L') }}
    B tile ;;
row_done:
    {{ store('H') }}
    DEC LR7 1 ; BEQ LR7 CR1 head_done ; INC.MODP2 LR6 CR1 7 ;;
    BNE LR6 CR0 query ;;
    INC LR5 1 ; B query ;;
head_done:
    ADD LR4 LR4 {{ cr.strides }}.H ; SET LR8 LR10 ; SET LR9 LR11 ;;
    DEC LR15 1 ; BNE LR15 CR1 head ;;
    ADD LR2 LR2 {{ cr.rhs_group }} ; DEC LR1 1 ; BNE LR1 CR1 group ;;
    HALT ;;
