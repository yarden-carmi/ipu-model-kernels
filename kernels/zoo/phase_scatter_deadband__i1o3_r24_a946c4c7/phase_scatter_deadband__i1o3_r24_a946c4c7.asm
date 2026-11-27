    SET LR15 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR11 CR0 ; SET LR12 CR0 ;;
y_loop:
    SET LR6 CR0 ; SET LR7 CR0 ; SET LR8 CR0 ;;
    SET LR13 CR0 ;;
channel_loop:
    SET LR0 CR0 ; SET LR1 {{ cr.pair }} ; SET LR2 CR0 ;;
    SET LR3 {{ cr.pair }} ;;
    ADDB LRD0 LR6 ;;
    ADDB LRD0 LR11 ;;
    ADDB LRD0 LR11 ;;
    ADD LR10 LR5 LR8 ; SET LR9 CR0 ;;
x_loop:
    LD.MULT R0 LR10 {{ cr.in0 }} ;;
    MULT.VE LR15 CR1 0 LR15 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD0 LRD2 6 ;;
    ADDBI LRD2 2 ; ADD LR10 LR10 {{ cr.chunks }} ; INC LR9 1 ;;
    BLT.S LR9 {{ cr.w }} x_loop ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
    INC LR4 1 ; INC LR13 1 ; INC LR7 1 ;;
    INC LR6 4 ;;
    BLT.S LR7 {{ cr.groupsize }} group_ok ;;
    SET LR7 CR0 ; SET LR6 CR0 ; INC LR8 1 ;;
group_ok:
    BLT.S LR13 {{ cr.cout }} channel_loop ;;
    INC LR11 1 ; INC LR12 1 ;;
    BLT.S LR11 {{ cr.kh }} phase_ok ;;
    SET LR11 CR0 ; ADD LR5 LR5 {{ cr.ystep }} ;;
phase_ok:
    BLT.S LR12 {{ cr.totaly }} y_loop ;;
    HALT ;;
