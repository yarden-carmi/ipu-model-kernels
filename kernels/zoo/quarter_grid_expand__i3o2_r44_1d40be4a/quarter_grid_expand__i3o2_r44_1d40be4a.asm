    SET LR15 {{ cr.planes }} ; SET LR14 CR0 ; SET LR13 CR0 ;;
plane:
    SET LR12 {{ cr.out0_d3 }} ; SET LR11 CR0 ; SET LR10 CR0 ;;
    DEC LR10 1 ; SET LR6 CR0 ;;
pair:
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR7 CR0 ;;
column:
    SET LR0 LR14 ; SET LR1 LR11 ; SET LR2 {{ cr.h }} ;;
source_y:
    LD.MULT R0 LR0 {{ cr.in0 }} ;;
    SET LR3 {{ cr.four }} ; BNE LR2 {{ cr.h }} no_first ;;
    INC LR3 1 ;;
no_first:
    BNE LR2 CR1 no_last ;;
    INC LR3 1 ;;
no_last:
    NOP ;;
replicate:
    SET LR4 CR0 ;;
    MULT.EE LR1 CR1 0 LR4 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD4 LRD8 7 ;;
    ADDBI LRD8 1 ; INC LR7 1 ; DEC LR3 1 ;;
    BNE LR7 {{ cr.lanes }} not_full ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; SET LR8 CR0 ; SET LR9 CR0 ;;
    SET LR7 CR0 ;;
not_full:
    BNE LR3 CR0 replicate ;;
    ADD LR1 LR1 {{ cr.w }} ; DEC LR2 1 ;;
    BLT.S LR1 {{ cr.eight_w }} row_ok ;;
    SUB LR1 LR1 {{ cr.eight_w }} ; INC LR0 1 ;;
row_ok:
    BNE LR2 CR0 source_y ;;
    DEC LR12 1 ; INC LR10 1 ;;
    BNE LR10 {{ cr.four }} x_ok ;;
    SET LR10 CR0 ; BEQ LR11 LR5 x_ok ;;
    INC LR11 1 ;;
x_ok:
    BNE LR12 CR0 more_columns ;;
    BEQ LR12 CR0 end_pair ;;
more_columns:
    BNE LR12 {{ cr.out0_d3 }} x_continue ;;
x_continue:
    BNE LR6 CR0 end_pair ;;
    SET LR6 CR1 ; BEQ LR12 LR12 column ;;
end_pair:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR13 ;;
    INC LR13 1 ; SET LR6 CR0 ;;
    BNE LR12 CR0 pair ;;
    ADD LR14 LR14 {{ cr.stride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 plane ;;
    HALT ;;
