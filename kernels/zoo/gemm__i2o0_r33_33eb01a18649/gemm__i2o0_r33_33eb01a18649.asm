    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR10 {{ cr.out0_d1 }} ;;
row:
    SET LR4 CR0 ; SET LR9 {{ cr.n }} ;;
channel:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; SET LR6 LR8 ; SET LR7 {{ cr.chunks }} ; INC LR4 1 ;;
chunk:
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; SET LR2 LR6 ; SET LR3 CR0 ;;
batch:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR3 {{ cr.full }}.L ; ADD LR2 LR2 {{ cr.batchstride }} ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.in0_d0 }} batch ;;
    INC LR4 1 ; INC LR6 1 ; DEC LR7 1 ; BNE LR7 CR1 chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; DEC LR9 1 ;;
    INC LR5 1 ; BNE LR9 CR0 channel ;;
    ADD LR8 LR8 {{ cr.chunks }} ; DEC LR10 1 ; BNE LR10 CR1 row ;;
    HALT ;;
