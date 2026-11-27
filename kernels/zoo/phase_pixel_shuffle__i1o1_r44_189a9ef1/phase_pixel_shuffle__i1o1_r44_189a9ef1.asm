    SET LR6 CR0 ; SET LR4 CR0 ; SET LR8 CR0 ;;
    SET LR9 CR0 ; SET LR12 CR0 ;;
batch:
    SET LR13 CR0 ;;
yloop:
    SET LR14 CR0 ;;
xloop:
    SET LR0 {{ cr.src_lo }} ; SET LR1 {{ cr.src_hi }} ; SET LR11 LR4 ;;
    SET LR5 CR0 ;;
aloop:
    SET LR7 CR0 ;;
bloop:
    SET LR2 {{ cr.dst_lo }} ; SET LR3 {{ cr.dst_hi }} ; SET LR10 LR6 ;;
    ADD LR8 LR6 {{ cr.input_rows }} ;;
rowloop:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
    MULT.VE LR9 CR1 0 LR9 {{ cr.active }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
    ADDBI LRD2 8 ; INC LR10 1 ;;
    BLT.S LR10 LR8 rowloop ;;
    ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR11 ;;
    ADDBI LRD0 1 ; INC LR11 1 ; INC LR7 1 ;;
    BLT.S LR7 LR15 bloop ;;
    ADD LR11 LR11 {{ cr.row_gap }} ; INC LR5 1 ;;
    BLT.S LR5 LR15 aloop ;;
    ADD LR6 LR6 {{ cr.input_rows }} ; INC LR4 {{ s }} ; INC LR14 1 ;;
    BLT.S LR14 {{ cr.in0_d3 }} xloop ;;
    {% if s > 1 %}INC LR4 {{ (s - 1) * out0_d3 }} ;;{% endif %}
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.in0_d2 }} yloop ;;
    INC LR12 1 ;;
    BLT.S LR12 {{ cr.in0_d0 }} batch ;;
    HALT ;;
