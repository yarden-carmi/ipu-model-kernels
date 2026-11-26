    SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0 ;;
    SET LR5 CR0 ; SET LR8 CR0 ; SET LR9 CR0 ;;
batch:
    SET LR10 CR0 ; SET LR11 CR0 ; SET LR4 CR0 ;;
pixel:
    ADD LR12 LR5 LR11 ; SET LR13 CR0 ;;
chunk:
    SET LR2 CR0 ; SET LR3 CR0 ; SET LR6 LR12 ;;
    SET LR7 CR0 ;;
    LD.MULT R0 LR6 {{ cr.in0 }} ;;
    MULT.EE LR4 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
gather:
    LD.MULT R0 LR6 {{ cr.in0 }} ; INC LR7 1 ;;
    MULT.EE LR4 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 7 ; ADD LR6 LR6 {{ cr.stride }} ;;
    ADDBI LRD2 1 ; BNE LR7 {{ cr.width }} gather ;;
    ACTIVATE.QUANTIZE {{ act_out0 }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
    INC LR8 1 ; ADD LR12 LR12 {{ cr.chunk_stride }} ; INC LR13 1 ;;
    BNE LR13 {{ cr.chunks }} chunk ;;
    INC LR4 1 ; INC LR10 1 ;;
    BNE LR4 {{ cr.lanes }} no_reset ;;
    SET LR4 CR0 ; INC LR11 1 ;;
no_reset:
    BNE LR10 {{ cr.in0_d2 }} pixel ;;
    ADD LR5 LR5 {{ cr.batch_stride }} ; INC LR9 1 ;;
    BNE LR9 {{ cr.in0_d0 }} batch ;;
    HALT ;;
