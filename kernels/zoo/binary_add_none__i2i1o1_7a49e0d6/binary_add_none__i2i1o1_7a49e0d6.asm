// out[h, w][c] = in0[c, w][h] + in1[h, w][c]: in0 holds h along the lanes (rows c, w),
// the output and in1 hold c along the lanes (rows h, w). One in0 element is picked with
// MULT.EE (broadcast) and scattered to lane c of R_ACC with ACC.RESHAPE; then in1 is added.
    SET LR6 CR0 ; SET LR9 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ;;
hloop:
    SET LR7 CR0 ;;
wloop:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR8 CR0 ;;
    ADD LR1 LR7 CR0 ;;
    LD.MULT R0 LR1 {{ cr.in0 }} ; B cmid ;;
cloop:
    ADD LR1 LR1 {{ cr.in0_d3 }} ; ADDBI LRD2 1 ; INC LR8 1 ; LD.MULT R0 LR1 {{ cr.in0 }} ;;
cmid:
    MULT.EE LR6 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD2 0 ; BLT.S LR8 {{ cr.cm1 }} cloop ;;
    LD.MULT R0 LR9 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.dsc }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.dsc }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR9 ;;
    INC LR9 1 ; INC LR7 1 ;;
    BLT.S LR7 {{ cr.in0_d3 }} wloop ;;
    INC LR6 1 ;;
    BLT.S LR6 {{ cr.in0_d2 }} hloop ;;
    HALT ;;
