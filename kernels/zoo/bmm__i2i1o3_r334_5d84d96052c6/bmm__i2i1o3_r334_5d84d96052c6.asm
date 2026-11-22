    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ;;
head:
    SET LR7 LR1 ; SET LR8 CR0 ;;
row:
    SET LR10 CR0 ;;
tile:
    ADD LR9 LR3 LR10 ; SET LR11 LR7 ; SET LR12 {{ cr.k }} ;;
    SET LR15 LR2 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
{% macro product(first) %}
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR0 ;;
    MULT.RC.VE LR0 LR15 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    INC.MODP2 LR15 CR1 7 ; DEC LR12 1 ; ADD LR9 LR9 {{ cr.bstep }} ;;
    BEQ LR12 CR0 store ;;
    BNE LR15 CR0 inner ;;
    INC LR11 1 ;;
    LD.MULT R0 LR11 {{ cr.in0 }} ;;
    B inner ;;
store:
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.nc }} full ;;
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    ADD LR7 LR7 {{ cr.ac }} ; INC LR8 1 ; INC LR4 1 ;;
    BLT.S LR8 {{ cr.m }} row ;;
    INC LR5 1 ;;
    BEQ LR5 {{ cr.b }} done ;;
    SUB LR3 LR9 LR10 ; INC LR6 1 ; ADD LR2 LR2 {{ cr.k }} ;;
    INC LR3 1 ;;
    SET LR11 CR0 ;;
    INC LR11 128 ;;
normalize:
    BLT.S LR2 LR11 normalized ;;
    SUB LR2 LR2 LR11 ; INC LR1 1 ;;
    B normalize ;;
normalized:
    BLT.S LR6 {{ cr.heads }} head ;;
    ADD LR1 LR1 LR14 ; ADD LR3 LR3 LR13 ; SET LR6 CR0 ;;
    SET LR2 CR0 ;;
    B head ;;
full:
    ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ;;
    B tile ;;
done:
    HALT ;;
