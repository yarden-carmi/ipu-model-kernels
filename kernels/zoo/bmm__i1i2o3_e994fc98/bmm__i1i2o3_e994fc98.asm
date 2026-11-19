    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR2 ;;
column:
    SET LR6 CR0 ;;
tile:
    ADD LR7 LR1 LR6 ; SET LR8 LR5 ; SET LR9 LR11 ;;
    SET LR12 CR0 ;;
{% macro product(first) %}
    LD.MULT R0 LR8 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR9 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    ADD LR7 LR7 {{ cr.arows }} ; INC.MODP2 LR9 CR1 7 ; INC LR12 1 ;;
    BNE LR9 CR0 same_chunk ;;
    INC LR8 1 ;;
same_chunk:
    BLT.S LR12 {{ cr.k }} inner ;;
    INC LR6 1 ;;
    BEQ LR6 {{ cr.mchunks }} tail ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
    INC LR10 1 ;;
    B tile ;;
tail:
    ACTIVATE.QUANTIZE identity {{ cr.dstail }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
    INC LR10 1 ; INC LR4 1 ; ADD LR5 LR5 {{ cr.brows }} ;;
    BLT.S LR4 {{ cr.n }} column ;;
    SET LR12 CR0 ;;
head_stride:
    ADD LR1 LR1 {{ cr.arows }} ; INC.MODP2 LR11 CR1 7 ;;
    BNE LR11 CR0 head_same_chunk ;;
    INC LR2 1 ;;
head_same_chunk:
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.k }} head_stride ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.b }} head ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 LR15 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR13 CR0 ;;
t_head:
    SET LR5 CR0 ; SET LR6 CR0 ; SET LR7 LR1 ;;
t_row:
    SET LR8 LR7 ; SET LR9 CR0 ; SET LR11 CR0 ;;
    SET LR4 CR0 ;;
t_col:
    LD.MULT R0 LR8 {{ cr.tmp }} ;;
    MULT.EE LR6 CR1 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD12 LRD10 7 ;;
    ADD LR8 LR8 {{ cr.mchunks }} ; INC LR9 1 ;;
    ADDBI LRD10 1 ;;
    BEQ LR9 {{ cr.n }} t_tail ;;
    SET LR12 CR0 ;;
    INC LR12 128 ;;
    INC LR4 1 ;;
    BLT.S LR4 LR12 t_col ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L CR0 LR2 ;;
    INC LR2 1 ; SET LR11 CR0 ; SET LR4 CR0 ;;
    B t_col ;;
t_tail:
    ACTIVATE.QUANTIZE identity {{ cr.dstail }}.H {{ cr.qf_out0 }}.L CR0 LR2 ;;
    INC LR2 1 ; INC LR5 1 ; INC.MODP2 LR6 CR1 7 ;;
    BNE LR6 CR0 t_same ;;
    INC LR7 1 ;;
t_same:
    BLT.S LR5 LR14 t_row ;;
    SET LR9 CR0 ;;
t_stride:
    ADD LR1 LR1 {{ cr.mchunks }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.n }} t_stride ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.b }} t_head ;;
    HALT ;;
