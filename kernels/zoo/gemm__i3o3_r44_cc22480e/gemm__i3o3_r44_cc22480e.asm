    SET LR0 CR0 ; SET LR1 CR0 ; SET LR5 CR0 ;;
    INC LR1 128 ; SET LR12 LR15 ; SET LR13 CR0 ;;
    DEC LR5 1 ;;
batch:
    SET LR10 CR0 ; SET LR11 {{ cr.n }} ;;
feature:
    SET LR8 {{ cr.opitch }} ; SET LR9 LR13 ;;
spatial:
    SET LR4 LR10 ; SET LR6 LR9 ; SET LR7 {{ cr.k }} ;;
    DEC LR4 1 ; SUB LR6 LR6 {{ cr.pitch }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR1 ; INC LR4 1 ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR1 ; INC LR4 1 ;;
    MULT.RC.VE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR6 {{ cr.in0 }} ; ADD LR6 LR6 {{ cr.pitch }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR1 ; INC LR4 1 ;;
channel:
    MULT.RC.VV LR1 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR1 ; INC LR4 1 ;;
    MULT.RC.VV LR1 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR7 1 ; BEQ LR7 CR1 finish ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ; ADD LR6 LR6 {{ cr.pitch }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR1 ; INC LR4 1 ; B channel ;;
finish:
    BEQ LR8 CR1 last_spatial ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR9 1 ; DEC LR8 1 ;;
    BNE LR8 CR0 spatial ;;
last_spatial:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    ADD LR10 LR10 {{ cr.weights }} ; DEC LR11 1 ; BNE LR11 CR1 feature ;;
    ADD LR13 LR13 {{ cr.batchstride }} ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    HALT ;;
