    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;

// Gather one K coordinate across the stored RHS rows into one scratch row.
transpose_k:
    SET LR5 LR2 ; SET LR7 CR0 ;;
    SET LR12 CR0 ; SET LR13 CR0 ;;
transpose_lane:
    LD.MULT R0 LR5 {{ cr.in1 }} ;;
    MULT.EE LR1 CR1 0 LR14 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.RESHAPE LRD14 LRD12 7 ;;
    ADDBI LRD12 1 ; ADD LR5 LR5 LR4 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.n }} transpose_lane ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout }}.L {{ cr.qf_in1 }}.L {{ cr.trans }} LR3 ;;
    INC LR3 1 ; INC.MODP2 LR1 CR1 7 ;;
    BNE LR1 CR0 transpose_same ;;
    INC LR2 1 ;;
transpose_same:
    BLT.S LR3 LR10 transpose_k ;;

    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ;;
row:
    SET LR7 LR2 ; SET LR8 LR3 ; SET LR9 CR0 ;;
    SET LR6 LR5 ;;
{% macro product(first) %}
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.trans }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsout }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    INC LR7 1 ; INC LR9 1 ; INC.MODP2 LR8 CR1 7 ;;
    BNE LR8 CR0 same_chunk ;;
    INC LR6 1 ;;
same_chunk:
    BLT.S LR9 {{ cr.k }} inner ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsout }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    INC LR10 1 ; ADD LR5 LR5 {{ cr.arows }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.m }} row ;;
    ADD LR2 LR2 {{ cr.k }} ; INC LR11 1 ; ADD LR3 LR3 {{ cr.k }} ;;
    SET LR12 CR0 ;;
    INC LR12 128 ;;
head_normalize:
    BLT.S LR3 LR12 head_ready ;;
    SUB LR3 LR3 LR12 ; INC LR1 1 ;;
    B head_normalize ;;
head_ready:
    BLT.S LR11 {{ cr.b }} head ;;
    HALT ;;
