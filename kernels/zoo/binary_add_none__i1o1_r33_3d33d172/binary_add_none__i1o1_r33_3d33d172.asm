    SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
    SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
    SET LR6 CR0 ; SET LR7 CR0 ;;
row:
    SET LR8 LR4 ; SET LR9 CR0 ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.EE LR3 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.one }}.L ;;
    INC LR9 1 ; INC LR8 {{ (in0_d1 + 127) // 128 }} ;;
gather:
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    BEQ LR9 LR10 finish_full ;;
    ADD LR11 LR5 LR9 ;;
    BGE.S LR11 {{ cr.out0_d1 }} finish_tail ;;
    LD.MULT R0 LR8 {{ cr.in0 }} ;;
    MULT.EE LR3 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR9 {{ cr.one }}.L ;;
    INC LR9 1 ; INC LR8 {{ (in0_d1 + 127) // 128 }} ; B gather ;;
finish_full:
    LD.MULT R0 LR1 {{ cr.constant }} ;;
    MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_constant }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ; B advance ;;
finish_tail:
    LD.MULT R0 LR1 {{ cr.constant }} ;;
    MULT.VE LR0 CR1 0 LR0 {{ cr.tail }}.L {{ cr.qf_constant }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
advance:
    INC LR1 1 ;;
    BEQ LR1 {{ cr.rows }} done ;;
    INC LR5 128 ; ADD LR4 LR4 {{ cr.blockstride }} ;;
    BLT.S LR5 {{ cr.out0_d1 }} row ;;
    SET LR5 CR0 ; INC LR3 1 ; INC LR6 1 ;;
    SET LR4 LR7 ;;
    SET LR10 CR0 ;;
    INC LR10 128 ;;
    BLT.S LR3 LR10 lane_ok ;;
    SET LR3 CR0 ; INC LR7 1 ;;
    SET LR4 LR7 ;;
lane_ok:
    BLT.S LR6 {{ cr.out0_d2 }} row ;;
    SET LR6 CR0 ; SET LR3 CR0 ; ADD LR2 LR2 {{ cr.batchstride }} ;;
    SET LR7 LR2 ; SET LR4 LR2 ; B row ;;
done:
    HALT ;;
