{# A is physically interleaved by head in the view. Stream B along N
   and broadcast one A value at a time into the output tile. #}
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR11 CR0 ;;
    SET LR12 CR0 ;;
batch:
    SET LR5 CR0 ; SET LR1 LR12 ;;
row:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR8 LR1 ; SET LR9 CR0 ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ; SET LR10 CR0 ;;
{% macro product(first) %}
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR10 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR7 LR7 {{ cr.nchunks }} ; INC LR9 1 ;;
    INC.MODP2 LR10 CR1 7 ;;
{% endmacro %}
    SET LR0 CR0 ;;
    {{ product(true) }}
    B check_k ;;
inner:
    {{ product(false) }}
check_k:
    BGE.S LR9 {{ cr.k }} store ;;
    BNE LR10 CR0 inner ;;
    INC LR8 1 ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    B inner ;;
store:
    INC LR6 1 ;;
    BEQ LR6 {{ cr.nchunks }} tail ;;
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ;;
{% endmacro %}
    {{ output('L') }}
    B tile ;;
tail:
    {{ output('H') }}
    ADD LR1 LR1 {{ cr.arowstride }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row ;;
    ADD LR2 LR2 {{ cr.bstride }} ; INC LR4 1 ; INC LR11 1 ;;
    ADD LR12 LR12 LR14 ;;
    BNE LR11 LR15 next_batch ;;
    ADD LR2 LR2 {{ cr.bgap }} ; SET LR11 CR0 ;;
    SUB LR12 LR1 LR13 ;;
next_batch:
    BLT.S LR4 {{ cr.b }} batch ;;
    HALT ;;
