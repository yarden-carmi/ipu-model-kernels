    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR8 {{ cr.n }} ;;
channel:
    SET LR7 {{ cr.spatial }} ; SET LR9 CR0 ;;
spatial:
    SET LR2 LR9 ; SET LR3 LR6 ; SET LR4 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ;;
    INC LR3 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ;;
dot:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; LD.MULT.CYCLIC LR3 {{ cr.w }} LR0 ; ADD LR2 LR2 {{ cr.spatial }} ; INC LR3 1 ; DEC LR4 1 ; BNE LR4 CR1 dot ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR9 1 ; DEC LR7 1 ; BNE LR7 CR1 spatial ;;
    ADD LR6 LR6 {{ cr.weights }} ; DEC LR8 1 ; BNE LR8 CR1 channel ;;
    HALT ;;
