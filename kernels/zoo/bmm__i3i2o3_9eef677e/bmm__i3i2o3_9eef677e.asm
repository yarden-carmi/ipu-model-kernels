    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR15 CR0 ;;
    SET LR14 CR0 ;;
    INC LR14 128 ;;
head:
    SET LR5 CR0 ;;
row:
    SET LR6 CR0 ; SET LR7 LR2 ;;
tile:
    SET LR8 LR1 ; SET LR9 LR7 ; SET LR12 CR0 ;;
    SET LR13 CR0 ;;
{% macro product(first) %}
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR9 {{ cr.in1 }} LR15 ;;
    SET LR4 LR9 ;;
    ADD LR4 LR3 LR6 ;;
    INC LR4 128 ;;
    BLT.S LR4 {{ cr.n }} need_second_{{ first }} ;;
    SET LR4 {{ cr.n }} ;;
    SUB LR4 LR4 LR6 ;;
    ADD LR4 LR4 LR3 ;;
    BLE.S LR4 LR14 loaded_{{ first }} ;;
need_second_{{ first }}:
    SET LR4 LR9 ;;
    INC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR14 ;;
loaded_{{ first }}:
    MULT.RC.VE LR3 LR12 0 LR15 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    INC LR13 1 ; INC.MODP2 LR12 CR1 7 ; ADD LR9 LR9 {{ cr.brows }} ;;
    BNE LR12 CR0 same_chunk ;;
    INC LR8 1 ;;
same_chunk:
    BLT.S LR13 {{ cr.k }} inner ;;
    INC LR6 128 ;;
    BLT.S LR6 {{ cr.n }} full ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
    B stored ;;
full:
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR0 ;;
stored:
    INC LR0 1 ; INC LR7 1 ;;
    BLT.S LR6 {{ cr.n }} tile ;;
    ADD LR1 LR1 LR10 ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.m }} row ;;
    ADD LR3 LR3 {{ cr.n }} ;;
normalize:
    BLT.S LR3 LR14 ready ;;
    SUB LR3 LR3 LR14 ; INC LR2 1 ;;
    B normalize ;;
ready:
    SET LR4 CR0 ;;
    ADD LR4 LR2 CR0 ;;
    SET LR12 CR0 ;;
    SET LR13 CR0 ;;
    B head_count ;;
head_count:
    INC LR13 1 ;;
    ADD LR12 LR12 {{ cr.n }} ;;
    SET LR4 LR2 ;;
    SET LR8 CR0 ;;
multiply128:
    BEQ LR4 CR0 multiplied ;;
    ADD LR8 LR8 LR14 ; DEC LR4 1 ;;
    B multiply128 ;;
multiplied:
    ADD LR8 LR8 LR3 ;;
    BLT.S LR12 LR8 head_count ;;
    BLT.S LR13 {{ cr.b }} head ;;
    HALT ;;
