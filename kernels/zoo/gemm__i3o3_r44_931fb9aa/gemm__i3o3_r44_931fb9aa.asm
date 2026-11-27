    SET LR0 CR0 ; SET LR5 CR0 ; SET LR6 CR0 ;;
    SET LR15 {{ cr.in0_d0 }} ;;
batch:
    SET LR7 CR0 ; SET LR8 {{ cr.n }} ;;
channel:
    SET LR9 CR0 ; SET LR10 {{ cr.groups }} ;;
group:
    LD.MULT R0 LR7 {{ cr.w }} ; SET LR2 LR6 ;;
    MULT.EE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; INC LR7 1 ;;
    LD.MULT R0 LR7 {{ cr.w }} ; ADD LR2 LR2 LR9 ; SET LR3 CR0 ;;
    INC LR7 1 ;;
    LD.MULT R1 LR7 {{ cr.w }} ; SET LR4 {{ cr.slot }} ;;
    DEC LR4 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ;;
    BEQ {{ cr.k }} CR1 last_tap ;;
tap:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; ADD LR2 LR2 {{ cr.groups }} ; INC LR3 1 ; LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; BLT.S LR3 {{ cr.last }} tap ;;
last_tap:
    MULT.RC.VE LR0 LR3 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; INC LR4 1 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR9 1 ; DEC LR10 1 ;;
    DEC LR7 2 ;;
    BNE LR10 CR0 group ;;
    INC LR7 3 ; DEC LR8 1 ;;
    BNE LR8 CR0 channel ;;
    ADD LR6 LR6 {{ cr.batch_stride }} ; DEC LR15 1 ;;
    BNE LR15 CR0 batch ;;
    HALT ;;
