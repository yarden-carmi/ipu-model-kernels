    SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
    SET LR6 {{ cr.heads }} ; SET LR15 CR0 ; SET LR12 CR1 ;;
head:
    SET LR2 LR0 ; SET LR7 {{ cr.rows }} ;;
row_pair:
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR1 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR15 ; ADD LR2 LR2 {{ cr.astride }} ;;
    LD.MULT R0 LR2 {{ cr.in0 }} ;;
    MULT.VE LR1 CR1 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR12 ; ADD LR2 LR2 {{ cr.astride }} ;;
    LD.MULT R0 LR15 {{ cr.tmp }} ;;
    MULT.VE LR15 CR0 0 LR15 {{ cr.ds }}.H {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
    SET LR4 LR0 ; SET LR5 CR0 ;;
col0:
    LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR15 ;;
    MULT.RC.VV LR1 R0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.ds }}.L ;;
    ADD LR4 LR4 {{ cr.bstride }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.cols }} col0 ;;
    LD.MULT R0 LR12 {{ cr.tmp }} ;;
    SET LR4 LR0 ; SET LR5 LR14 ;;
col1:
    LD.MULT.CYCLIC LR4 {{ cr.in1 }} LR15 ;;
    MULT.RC.VV LR1 R0 0 LR15 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR5 {{ cr.ds }}.L ;;
    ADD LR4 LR4 {{ cr.bstride }} ; INC LR5 1 ;;
    BLT.S LR5 {{ cr.colend }} col1 ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
    INC LR3 1 ; DEC LR7 2 ;;
    BGT.S LR7 CR0 row_pair ;;
    INC LR1 64 ;;
    BLT.S LR1 LR13 next_head ;;
    SET LR1 CR0 ; INC LR0 1 ;;
next_head:
    DEC LR6 1 ;;
    BGT.S LR6 CR0 head ;;
    HALT ;;
