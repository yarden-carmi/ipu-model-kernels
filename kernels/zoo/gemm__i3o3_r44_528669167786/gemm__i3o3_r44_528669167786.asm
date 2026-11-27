    SET LR0 CR0 ; SET LR5 CR0 ; SET LR8 CR0 ;;
    SET LR10 {{ cr.n }} ;;
channel:
    SET LR6 {{ cr.chunks }} ; SET LR9 CR0 ;;
chunk:
    SET LR2 LR9 ; SET LR4 LR8 ; SET LR7 {{ cr.k }} ;;
    LD.MULT.CYCLIC LR4 {{ cr.w }} LR0 ;;
    INC LR4 1 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    DEC LR4 1 ; SUB LR2 LR2 {{ cr.chunks }} ;;
loop:
    LD.MULT R0 LR4 {{ cr.w }} ; INC LR4 1 ;;
    LD.MULT.CYCLIC LR2 {{ cr.in0 }} LR0 ; ADD LR2 LR2 {{ cr.chunks }} ;;
    MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ; DEC LR7 1 ; BNE LR7 CR1 loop ;;
    DEC LR6 1 ;;
    BEQ LR6 CR0 last ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR5 1 ; INC LR9 1 ; B chunk ;;
last:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
    INC LR4 1 ;;
    INC LR5 1 ; SET LR8 LR4 ; DEC LR10 1 ;;
    BNE LR10 CR0 channel ;;
    HALT ;;
