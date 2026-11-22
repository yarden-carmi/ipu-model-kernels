{# Stream M vectors from the LHS and broadcast K scalars from the RHS. #}
{% macro product(first) %}
    LD.MULT.CYCLIC LR9 {{ cr.in0 }} LR14 ;;
    MULT.RC.VE LR14 LR11 0 LR14 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; DEC LR12 1 ; ADD LR9 LR9 {{ cr.mc }} ;;
{% endmacro %}
{% macro output(half) %}
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.{{ half }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    INC LR0 1 ;;
{% endmacro %}

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR14 CR0 ;;
group:
    SET LR3 CR0 ; SET LR4 LR6 ;;
head:
    SET LR7 LR2 ; SET LR13 {{ cr.n }} ;;
column:
    SET LR8 {{ cr.mc }} ; SET LR15 LR1 ;;
tile:
    SET LR9 LR15 ; SET LR10 LR7 ; SET LR11 LR3 ;;
    SET LR12 {{ cr.k }} ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
    {{ product(true) }}
    B advance ;;
reload:
    INC LR10 1 ;;
    LD.MULT R0 LR10 {{ cr.in1 }} ;;
reduce:
    {{ product(false) }}
advance:
    BEQ LR12 CR0 store ; INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 reduce ;;
    B reload ;;
store:
    DEC LR8 1 ; INC LR15 1 ;;
    BEQ LR8 CR0 tail ;;
    {{ output('L') }}
    B tile ;;
tail:
    {{ output('H') }}
    ADD LR7 LR7 {{ cr.bstride }}.L ; DEC LR13 1 ;;
    BNE LR13 CR0 column ;;

    ADD LR3 LR3 {{ cr.k }} ; SET LR7 CR0 ; DEC LR4 1 ;;
    ADD LR1 LR1 {{ cr.a_head }} ;;
    INC LR7 128 ;;
normalize:
    BLT.S LR3 LR7 normalized ;;
    SUB LR3 LR3 LR7 ; INC LR2 1 ;;
    B normalize ;;
normalized:
    BNE LR4 CR0 head ;;
    ADD LR1 LR1 {{ cr.a_adjust }} ; ADD LR2 LR2 {{ cr.bstride }}.H ; DEC LR5 1 ;;
    BNE LR5 CR0 group ;;
    HALT ;;
