    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR14 CR0 ; SET LR15 CR0 ;;
    SET LR9 CR0 ;;
    INC LR9 128 ;;
transpose_feature:
    SET LR5 LR2 ; SET LR6 CR0 ; SET LR4 CR0 ;;
transpose_tile:
    SET LR12 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
transpose_lane:
    BGE.S LR4 {{ cr.m }} zero_lane ;;
    LD.MULT R0 LR5 {{ cr.in0 }} ;;
    MULT.EE LR1 CR1 0 LR14 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD12 0 ;;
    B lane_done ;;
zero_lane:
    MULT.EE LR1 CR0 0 LR14 {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD14 LRD12 0 ;;
lane_done:
    ADDBI LRD12 1 ; ADD LR5 LR5 LR10 ; INC LR7 1 ;;
    INC LR4 1 ;;
    BLT.S LR7 LR9 transpose_lane ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_in0 }}.L {{ cr.trans }} LR3 ;;
    INC LR3 1 ; INC LR6 1 ;;
    BLT.S LR6 {{ cr.mc }} transpose_tile ;;
    INC LR0 1 ; INC.MODP2 LR1 CR1 7 ;;
    BNE LR1 CR0 transpose_same ;;
    INC LR2 1 ;;
transpose_same:
    BLT.S LR0 LR11 transpose_feature ;;
    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR10 CR0 ; SET LR11 CR0 ;;
head:
    SET LR4 CR0 ; SET LR5 LR1 ;;
column:
    SET LR6 CR0 ; SET LR14 LR2 ;;
tile:
    SET LR7 LR14 ; SET LR8 LR3 ; SET LR9 CR0 ;;
    SET LR12 LR5 ;;
{% macro product(first) %}
    LD.MULT R0 LR12 {{ cr.in1 }} ;;
    LD.MULT.CYCLIC LR7 {{ cr.trans }} LR0 ;;
    MULT.RC.VE LR0 LR8 0 LR0 {{ cr.dsfull }}.L {{ cr.qf_in1 }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ;;
{% endmacro %}
    {{ product(true) }}
    B advance ;;
inner:
    {{ product(false) }}
advance:
    INC.MODP2 LR8 CR1 7 ; INC LR9 1 ; ADD LR7 LR7 {{ cr.mc }} ;;
    BNE LR8 CR0 same_chunk ;;
    INC LR12 1 ;;
same_chunk:
    BLT.S LR9 {{ cr.k }} inner ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.mc }} store_full ;;
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
    B stored ;;
store_full:
    ACTIVATE.QUANTIZE identity {{ cr.dsfull }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR10 ;;
stored:
    INC LR10 1 ; INC LR14 1 ;;
    BLT.S LR6 {{ cr.mc }} tile ;;
    ADD LR5 LR5 {{ cr.brows }} ; INC LR4 1 ;;
    BLT.S LR4 {{ cr.n }} column ;;
    SET LR12 CR0 ;;
head_offset:
    ADD LR2 LR2 {{ cr.mc }} ; INC LR12 1 ;;
    BLT.S LR12 {{ cr.k }} head_offset ;;
    INC LR11 1 ; ADD LR3 LR3 {{ cr.k }} ; SET LR12 CR0 ;;
    INC LR12 128 ;;
head_normalize:
    BLT.S LR3 LR12 head_ready ;;
    SUB LR3 LR3 LR12 ; INC LR1 1 ;;
    B head_normalize ;;
head_ready:
    BLT.S LR11 {{ cr.b }} head ;;
    HALT ;;
