    SET LR0 CR0 ; SET LR1 CR0 ; SUB LR2 LR0 CR1 ;;
height:
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
scale_block:
    LD.MULT R0 LR3 {{ cr.in1 }} ;;
    INC LR3 1 ;;
channel:
    LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 LR4 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ; INC LR1 1 ; INC LR2 1 ; INC LR5 1 ;;
    INC.MODP2 LR4 CR1 7 ; BEQ LR5 {{ cr.inner }} height_end ;;
    BEQ LR4 CR0 scale_block ;;
    B channel ;;
height_end:
    BLT.S LR1 {{ cr.rows }} height ;;
    HALT ;;
