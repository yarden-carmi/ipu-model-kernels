    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR8 CR0 ; SET LR9 CR0 ; SET LR10 CR0 ;;
    SET LR12 CR0 ;;
channel:
    SET LR5 LR10 ; SET LR11 CR0 ; ADD LR13 LR10 {{ cr.spatial }} ;;
chunk:
    SET LR6 LR5 ; SET LR7 CR0 ;;
sum_loop:
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR4 CR1 0 LR12 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR6 {{ cr.in1 }} ;;
    MULT.EE LR4 CR1 0 LR12 {{ cr.full }}.L {{ cr.qf_in1 }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR7 ;;
    INC LR7 1 ; INC LR6 1 ;;
    BEQ LR7 {{ cr.full_count }} sum_done ;;
    BLT.S LR6 LR13 sum_loop ;;
sum_done:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 LR5 ;;
    SET LR7 CR0 ;;
gather:
    LD.MULT R0 LR7 {{ cr.tmp }} ;;
    MULT.EE LR12 CR1 0 LR12 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ;;
    ADDBI LRD2 1 ; INC LR7 1 ; INC LR6 1 ;;
    BEQ LR7 {{ cr.full_count }} gather_done ;;
    BLT.S LR6 LR13 gather ;;
gather_done:
    BEQ LR11 {{ cr.last }} last_store ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    BEQ CR0 CR0 next_chunk ;;
last_store:
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
next_chunk:
    INC LR8 1 ; INC LR11 1 ; ADD LR5 LR5 {{ cr.full_count }} ;;
    BLT.S LR11 {{ cr.chunks }} chunk ;;
    INC LR9 1 ; INC LR4 1 ;;
    BLT.S LR9 {{ cr.out0_d1 }} channel ;;
    HALT ;;
