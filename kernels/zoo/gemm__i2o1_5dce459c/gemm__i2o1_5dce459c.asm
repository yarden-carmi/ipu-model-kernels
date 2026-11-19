    SET LR0 CR0 ;;
    SET LR8 CR0 ;;
    SET LR9 CR0 ;;
    SET LR10 CR0 ;;
    SET LR14 CR0 ;;
transpose_k:
    SET LR11 CR0 ;;
    SET LR12 LR9 ;;
transpose_block:
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    SET LR7 CR0 ;;
    SET LR13 CR0 ;;
transpose_lane:
    LD.MULT R0 LR12 {{ cr.in0 }} ;;
    MULT.EE LR8 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD6 7 ;;
    ADD LR12 LR12 {{ cr.K }} ; INC LR11 1 ; INC LR13 1 ;;
    ADD LR7 LR7 LR3 ;;
    BGE.S LR11 {{ cr.m }} transpose_store ;;
    BLT.S LR13 LR15 transpose_lane ;;
transpose_store:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.t }} LR10 ;;
    INC LR10 1 ;;
    BLT.S LR11 {{ cr.m }} transpose_block ;;
    INC.MODP2 LR8 CR1 7 ;;
    BNE LR8 CR0 transpose_next ;;
    INC LR9 1 ;;
transpose_next:
    INC LR14 1 ;;
    BLT.S LR14 {{ cr.k }} transpose_k ;;
    SET LR0 CR0 ;;
    SET LR1 CR0 ;;
    SET LR7 CR0 ;;
    SET LR9 CR0 ;;
n_loop:
    SET LR2 CR0 ;;
m_loop:
    SET LR3 LR2 ;;
    SET LR4 LR1 ;;
    SET LR5 CR0 ;;
    SET LR6 CR0 ;;
    MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
k_loop:
    LD.MULT R0 LR4 {{ cr.w }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.t }} LR0 ;;
    MULT.RC.VE LR0 LR5 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ADD LR3 LR3 {{ cr.MB }} ; INC LR6 1 ;;
    INC.MODP2 LR5 CR1 7 ;;
    BNE LR5 CR0 same_weight ;;
    INC LR4 1 ;;
same_weight:
    BLT.S LR6 {{ cr.k }} k_loop ;;
{% if bias %}
    LD.MULT R0 LR7 {{ cr.b }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
{% endif %}
    INC LR2 1 ;;
    BLT.S LR2 {{ cr.MB }} full_store ;;
    ACTIVATE.QUANTIZE identity {{ cr.tail_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    BEQ CR0 CR0 stored ;;
full_store:
    ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
stored:
    INC LR9 1 ;;
    BLT.S LR2 {{ cr.MB }} m_loop ;;
    ADD LR1 LR1 {{ cr.K }} ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.n }} n_loop ;;
    HALT ;;
