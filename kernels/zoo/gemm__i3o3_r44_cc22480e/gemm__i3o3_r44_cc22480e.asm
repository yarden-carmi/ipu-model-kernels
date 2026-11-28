    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR10 {{ cr.n }} ; SET LR11 {{ cr.batches }} ; DEC LR5 1 ;;
batch:
    SET LR9 CR0 ; SET LR10 {{ cr.n }} ;;
feature:
    SET LR12 {{ cr.pitch }} ; SET LR13 LR8 ;;
row:
    SET LR4 LR9 ; SET LR2 LR13 ; SET LR7 {{ cr.k }} ;;
    DEC LR4 1 ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ; INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
tap:
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ; ADD LR2 LR2 {{ cr.pitch }} ; DEC LR7 1 ;;
    BEQ LR7 CR0 finish ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; B tap ;;
finish:
    BEQ LR12 CR1 lastrow ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ; INC LR13 1 ; DEC LR12 1 ; B row ;;
lastrow:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ; INC LR5 1 ;;
    SET LR9 LR4 ; DEC LR10 1 ; BNE LR10 CR1 feature ;;
    ADD LR8 LR8 {{ cr.batch_stride }} ; DEC LR11 1 ; BNE LR11 CR1 batch ;;
    HALT ;;
