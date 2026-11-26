    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR10 {{ cr.out0_d1 }} ;;
row:
    SET LR3 {{ cr.n }} ; SET LR4 CR0 ;;
feature:
    LD.MULT R0 LR4 {{ cr.coeff }} ;;
    INC LR4 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR4 {{ cr.coeff }} ;;
    INC LR4 1 ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; SET LR11 LR4 ; SET LR5 CR0 ; SET LR6 LR2 ;;
batch:
    SET LR4 LR11 ; SET LR7 {{ cr.chunks }} ; SET LR8 LR6 ;;
chunk:
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ;;
    INC LR4 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.full }}.L ;;
    LD.MULT.CYCLIC LR4 {{ cr.coeff }} LR0 ;;
    INC LR4 1 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.full }}.L ; INC LR8 1 ; DEC LR7 1 ; BNE LR7 CR1 chunk ;;
    ADD LR6 LR6 {{ cr.batch_stride }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.out0_d0 }} batch ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ; DEC LR3 1 ; BNE LR3 CR1 feature ;;
    ADD LR2 LR2 {{ cr.chunks }} ; DEC LR10 1 ; BNE LR10 CR1 row ;;
    HALT ;;
