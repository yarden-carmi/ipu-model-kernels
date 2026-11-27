    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR9 CR0 ;;
    SET LR14 {{ cr.out0_d2 }} ;;
    DEC LR14 1 ;;
batch:
    SET LR4 CR0 ; SET LR5 CR0 ;;
channel:
    LD.MULT.CYCLIC LR5 {{ cr.w }} LR0 ;;
    INC LR5 1 ;;
    SET LR13 LR5 ;;
    INC LR5 1 ;;
    SET LR6 LR10 ; SET LR11 LR10 ;;
    INC LR11 128 ;;
    SET LR12 LR11 ;;
    INC LR12 128 ;;
    LD.MULT.CYCLIC LR5 {{ cr.w }} LR6 ;;
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.w }} LR11 ;;
    INC LR5 1 ;;
    LD.MULT.CYCLIC LR5 {{ cr.w }} LR12 ;;
width:
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    LD.MULT R0 LR13 {{ cr.w }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
    SET LR7 LR2 ; SET LR8 CR0 ;;
height:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.RC.VV LR6 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.valid }}.L ; ADD LR7 LR7 {{ cr.in0_d3 }} ;;
    MULT.RC.VV LR11 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.valid }}.L ;;
    MULT.RC.VV LR12 R0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR8 {{ cr.valid }}.L ;;
    INC LR8 1 ; BLT.S LR8 LR14 height ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.outvalid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; INC LR2 1 ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.out0_d3 }} width ;;
    SUB LR2 LR2 {{ cr.out0_d3 }} ; INC LR5 1 ; INC LR4 1 ;;
    SET LR9 CR0 ; BLT.S LR4 {{ cr.out0_d1 }} channel ;;
    ADD LR2 LR2 {{ cr.spatial }} ; INC LR1 1 ;;
    BLT.S LR1 {{ cr.out0_d0 }} batch ;;
    HALT ;;
