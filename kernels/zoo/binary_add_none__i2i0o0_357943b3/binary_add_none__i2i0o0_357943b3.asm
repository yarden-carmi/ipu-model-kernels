    SET LR2 CR0 ;;
    INC LR2 128 ;;
    SET LR1 CR0 ;;
    SET LR3 CR0 ;;
    SET LR4 CR0 ;;
    SET LR5 CR0 ;;
    SET LR8 CR0 ;;
    SET LR9 CR0 ;;
loop:
    ADD LR11 LR5 LR5 ;;
    BLT.S LR4 {{ cr.c128 }} lo ;;
    INC LR11 1 ; SUB LR12 LR4 {{ cr.c128 }} ;;
    BEQ LR0 CR0 go ;;
lo:
    SET LR12 LR4 ;;
go:
    LD.MULT.CYCLIC LR11 {{ cr.in0 }} LR0 ;;
    LD.MULT R1 LR1 {{ cr.in1 }} ;;
    MULT.RC.VE LR12 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    MULT.VE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in1 }}.L ; ACC.ADD ;;
    INC LR3 1 ; INC LR5 7 ; INC LR4 16 ;;
    BLT.S LR4 {{ cr.c144 }} nc1 ;;
    SUB LR4 LR4 {{ cr.c144 }} ; INC LR5 1 ;;
nc1:
    ACTIVATE.QUANTIZE identity {{ cr.ds4 }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
    INC LR1 1 ;;
    BLT.S LR3 {{ cr.c144 }} samep ;;
    SET LR3 CR0 ; INC LR8 4 ;;
    BLT.S LR8 {{ cr.c144 }} nc2 ;;
    SUB LR8 LR8 {{ cr.c144 }} ; INC LR9 1 ;;
nc2:
    SET LR4 LR8 ; SET LR5 LR9 ;;
samep:
    BLT.S LR1 {{ cr.rows }} loop ;;
    HALT ;;
