{# Each K step reads a vector of M and broadcasts one N lane. #}
    SET LR0 CR0 ; SET LR3 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR10 CR0 ; SET LR14 CR0 ;;
head:
    SET LR11 CR0 ; SET LR12 CR0 ; SET LR13 CR0 ;;
column:
    SET LR9 CR0 ;;
tile:
    ADD LR6 LR4 LR9 ; ADD LR7 LR5 LR13 ; SET LR8 CR0 ;;
{% macro product(first) %}
    LD.MULT R0 LR7 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR6 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR12 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; INC LR8 1 ; ADD LR7 LR7 {{ cr.nc }} ; ADD LR6 LR6 {{ cr.mc }} ;;
{% endmacro %}
    {{ product(true) }}
    B check_k ;;
inner:
    {{ product(false) }}
check_k:
    BLT.S LR8 {{ cr.k }} inner ;;
    INC LR9 1 ;;
    BEQ LR9 {{ cr.mc }} tail ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ;;
    B tile ;;
tail:
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR11 1 ; INC.MODP2 LR12 CR1 7 ;;
    BNE LR12 CR0 same_chunk ;;
    INC LR13 1 ;;
same_chunk:
    BLT.S LR11 {{ cr.n }} column ;;
    {# Recover the next head bases from the last dot product's end addresses. #}
    DEC LR9 1 ;;
    BEQ LR12 CR0 wrapped ;;
    B next_head ;;
wrapped:
    DEC LR13 1 ;;
next_head:
    SUB LR4 LR6 LR9 ; SUB LR5 LR7 LR13 ; INC LR14 1 ;;
    INC LR3 1 ;;
    BNE LR14 {{ cr.heads }} more ;;
    ADD LR4 LR4 {{ cr.gap0 }} ; ADD LR5 LR5 {{ cr.gap1 }} ; SET LR14 CR0 ;;
more:
    BLT.S LR3 LR15 head ;;
    HALT ;;
