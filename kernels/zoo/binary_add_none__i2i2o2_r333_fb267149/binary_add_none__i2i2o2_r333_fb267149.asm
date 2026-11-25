// The view consumes in0[d0*(j + d1*k) + a] in output order (a,j,k).
// Gather lanes from the packed in0 stream into one accumulator row.
    INC LR13 128 ;;
start_j:
    SET LR6 LR8 ;;
    SET LR7 LR9 ;;
    SET LR10 CR0 ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.VE LR7 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7 ; INC LR14 1 ;;
    BEQ LR14 LR13 store ; ADDBI LRD4 1 ;;
    B advance ;;
store:
    LD.MULT R0 LR1 {{ cr.in1 }} ; SET LR4 LR2 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; SET LR5 LR3 ;;
    INC LR1 1 ;;
    SET LR14 CR0 ;;
advance:
    INC LR10 1 ;;
    BEQ LR10 {{ cr.out0_d2 }} next_j ;;
    ADD LR6 LR6 {{ cr.skip_rows }} ;;
    ADD LR7 LR7 {{ cr.skip_lanes }} ;;
    BLT.S LR7 LR13 gather ;;
    INC LR6 1 ;;
    DEC LR7 128 ; B gather ;;
next_j:
    INC LR11 1 ;;
    BEQ LR11 {{ cr.out0_d1 }} next_a ;;
    ADD LR9 LR9 {{ cr.out0_d0 }} ;;
normalize_j:
    BLT.S LR9 LR13 start_j ;;
    INC LR8 1 ;;
    DEC LR9 128 ; B normalize_j ;;
next_a:
    INC LR15 1 ;;
    BEQ LR15 {{ cr.out0_d0 }} finish ;;
    SET LR11 CR0 ;;
    SET LR8 CR0 ;;
    SET LR9 LR15 ; B normalize_j ;;
finish:
    HALT ;;
