    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ; SET LR13 CR0 ;;
row:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR2 LR6 ; SET LR9 CR0 ; SET LR12 LR5 ;;
{% macro product(first) %}
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR13 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    ADD LR12 LR12 {{ cr.arows }} ; INC LR9 1 ; ADD LR7 LR7 {{ cr.nchunks }} ;;
    BLT.S LR9 {{ cr.k }} inner ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.nchunks }} tail ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ;;
    B tile ;;
tail:
    ACTIVATE.QUANTIZE identity {{ cr.dstail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; INC LR4 1 ; INC.MODP2 LR13 CR1 7 ;;
    BNE LR13 CR0 same_row ;;
    INC LR5 1 ;;
same_row:
    BLT.S LR4 {{ cr.m }} row ;;
    SET LR12 CR0 ;;
head_stride:
    ADD LR1 LR1 {{ cr.arows }} ; ADD LR2 LR2 {{ cr.nchunks }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.k }} head_stride ;;
    INC LR11 1 ;;
    BLT.S LR11 {{ cr.b }} head ;;
    HALT ;;
