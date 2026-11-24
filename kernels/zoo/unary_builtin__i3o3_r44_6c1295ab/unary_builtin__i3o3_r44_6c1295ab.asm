{# Traverse output in (channel, batch, height) order. Input height stride is C. #}
    SET LR2 CR0 ; SET LR3 CR0 ;;
channel:
    SET LR4 CR0 ; SET LR5 LR3 ;;
batch:
    SET LR6 CR0 ; SET LR7 LR5 ;;
height:
    LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ;;
    MULT.RC.VE LR0 CR1 0 LR0 {{ cr.active_in }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active_out }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
    INC LR2 1 ; INC LR6 1 ; ADD LR7 LR7 {{ cr.in0_d1 }} ; BLT.S LR6 {{ cr.last_height }} height ;;
    INC LR4 1 ; ADD LR5 LR5 {{ cr.batch_stride }} ;;
    BLT.S LR4 {{ cr.in0_d0 }} batch ;;
    INC LR3 1 ;;
    BLT.S LR3 {{ cr.in0_d1 }} channel ;;
    HALT ;;
