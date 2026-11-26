    SET LR15 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR10 CR0 ;;
    SET LR0 {{ cr.src }} ; SET LR1 {{ cr.src }} ;;
channel:
    SET LR7 LR6 ; SET LR8 CR0 ;;
row:
    SET LR2 {{ cr.dst }} ; SET LR3 {{ cr.dst }} ; SET LR9 CR0 ;;
site:
    LD.MULT R0 LR7 {{ cr.in0 }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 0 ;;
    ADDBI LRD2 2 ; ADD LR7 LR7 {{ cr.chunks }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.w }} site ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR8 1 ;;
    BLT.S LR8 {{ cr.h }} row ;;
    ADDBI LRD0 4 ; INC LR5 1 ;;
    INC LR10 1 ;;
    BLT.S LR10 {{ cr.channels_per_chunk }} same_chunk ;;
    SET LR10 CR0 ; INC LR6 1 ; SET LR0 {{ cr.src }} ;;
    SET LR1 {{ cr.src }} ;;
same_chunk:
    BLT.S LR5 {{ cr.channels }} channel ;;
    HALT ;;
