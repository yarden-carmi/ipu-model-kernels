{# Each accumulator lane is a query. Stage a chunk of one RHS column
   in R0 and stream query vectors from the producer's key-major layout. #}
{% macro mac(prefetch) %}
    MULT.RC.VE LR15 LR12 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR12 1
    {%- if prefetch %} ; ADD LR8 LR8 {{ cr.a_key }} ; LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR15 ; DEC LR3 1 ; BGT.S LR3 {{ cr.two }} key{% endif %} ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0
{%- endmacro %}

    SET LR0 CR0 ; SET LR2 CR0 ; SET LR7 CR0 ;;
    SET LR13 CR0 ; SET LR15 CR0 ;;
    INC LR13 128 ;;
group:
    SET LR4 {{ cr.out0_d1 }} ;;
head:
    SET LR5 {{ cr.n }} ;;
column:
    SET LR6 {{ cr.m }} ;;
tile:
    SET LR8 LR2 ; SET LR9 LR7 ; SET LR10 {{ cr.k }} ;
    MULT.VE LR13 CR0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in1 }}.L ; ACC.ADD.FIRST ;;
chunk:
    SET LR3 LR10 ; BLE.S LR10 LR13 chunk_ready ;;
    SET LR3 LR13 ;;
chunk_ready:
    LD.MULT R0 LR9 {{ cr.in1 }} ; SUB LR10 LR10 LR3 ; SET LR12 CR0 ;;
    LD.MULT.CYCLIC LR8 {{ cr.in0 }} LR15 ; DEC LR12 1 ; BEQ LR3 CR1 drain ;;
key:
    {{ mac(true) }}
drain:
    {{ mac(false) }}
    BEQ LR10 CR0 store ;;
    ADD LR8 LR8 {{ cr.a_key }} ; INC LR9 1 ; B chunk ;;
store:
    BGT.S LR6 LR13 full ;;
    {{ output('H') }} ; ADD LR7 LR7 {{ cr.chunks }}.H ; DEC LR5 1 ;;
    SUB LR2 LR2 {{ cr.chunks }}.L ; INC LR0 1 ;;
    INC LR2 1 ; BGT.S LR5 CR0 column ;;
    B next_head ;;
full:
    {{ output('L') }} ; DEC LR6 128 ; INC LR2 1 ;;
    INC LR0 1 ; B tile ;;
next_head:
    ADD LR2 LR2 {{ cr.chunks }}.L ; DEC LR4 1 ;;
    BGT.S LR4 CR0 head ;;
    ADD LR2 LR2 LR11 ; ADD LR7 LR7 LR14 ; DEC LR1 1 ;;
    BGT.S LR1 CR0 group ;;
    HALT ;;
