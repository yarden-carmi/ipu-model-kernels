    INC LR6 128 ; SET LR10 CR8 ;;
    DEC LR10 1 ; DEC LR1 1 ;;
column:
    SET LR4 CR0 ; SET LR5 LR2 ;;
tile:
    LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR0 ; ADD LR7 LR5 CR1 ; INC LR1 1 ;;
    BGE.S LR5 {{ cr.last }} no_second ;;
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR6 ;;
no_second:
    MULT.RC.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR1 {{ cr.in1 }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ; BEQ LR4 LR10 tail ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR5 1 ; INC LR4 1 ; B tile ;;
tail:
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; INC LR9 1 ;;
    ADD LR2 LR2 {{ cr.step }} ; ADD LR3 LR3 {{ cr.rem }} ;;
    BLT.S LR3 LR6 nowrap ;;
    DEC LR3 128 ; INC LR2 1 ;;
nowrap:
    BLT.S LR9 {{ cr.out0_d2 }} column ;;
    HALT ;;
