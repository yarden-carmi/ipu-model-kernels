    SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
    SET LR10 {{ cr.n }} ; SET LR15 {{ cr.weight_stride }} ;;
    DEC LR15 1 ; DEC LR2 1 ;;
channel:
    SET LR4 CR0 ; SET LR11 {{ cr.out0_d1 }} ;;
row:
    LD.MULT R0 LR3 {{ cr.w }} ;;
    SET LR6 CR0 ; SET LR12 {{ cr.out0_d0 }} ;;
    DEC LR6 1 ;;
bias:
    MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.one }}.L ; INC LR6 1 ; DEC LR12 1 ; BNE LR12 CR1 bias ;;
    SET LR7 LR3 ; SET LR8 LR4 ; SET LR9 LR15 ;;
chunk:
    INC LR7 1 ; SUB LR5 LR8 {{ cr.batch_stride }} ; SET LR6 CR0 ;;
    DEC LR6 1 ;;
    LD.MULT.CYCLIC LR7 {{ cr.w }} LR0 ; SET LR12 {{ cr.out0_d0 }} ; DEC LR9 1 ; BEQ LR9 CR1 last_chunk ;;
batch:
    LD.MULT R0 LR5 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.batch_stride }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.full }}.L ; INC LR6 1 ; DEC LR12 1 ; BNE LR12 CR1 batch ;;
    INC LR8 1 ; B chunk ;;
last_chunk:
    LD.MULT R0 LR5 {{ cr.in0 }} ; ADD LR5 LR5 {{ cr.batch_stride }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR6 {{ cr.tail }}.L ; INC LR6 1 ; DEC LR12 1 ; BNE LR12 CR1 last_chunk ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.out_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR2 1 ;;
    ADD LR4 LR4 LR15 ; DEC LR11 1 ; BNE LR11 CR1 row ;;
    ADD LR3 LR3 {{ cr.weight_stride }} ; DEC LR10 1 ; BNE LR10 CR1 channel ;;
    HALT ;;
