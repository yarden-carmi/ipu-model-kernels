{# Both operands have K along the lanes. Each dot writes one lane of
   the consumer's M-lane row, without requantizing either operand. #}
    SET LR0 CR0 ; SET LR8 CR0 ; SET LR11 CR0 ;;
    SET LR12 CR0 ;;
head:
    SET LR7 {{ cr.n }} ;;
column:
    LD.MULT R0 LR8 {{ cr.in1 }} ; SET LR10 LR11 ; SET LR13 CR0 ;;
dot:
    LD.MULT.CYCLIC LR10 {{ cr.in0 }} LR0 ;;
    MULT.RC.VV LR0 R0 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR13 {{ cr.ds }}.L ; INC LR10 1 ;;
    INC LR13 1 ;;
    BLT.S LR13 {{ cr.m }} dot ;;
    ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.ds }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR12 ;;
    INC LR12 1 ; INC LR8 1 ; DEC LR7 1 ;;
    BNE LR7 CR0 column ;;
    SET LR11 LR10 ; DEC LR15 1 ;;
    BNE LR15 CR0 head ;;
    HALT ;;
