SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR15 CR0 ;;
batch_loop:
SET LR11 LR1 ; SET LR3 CR0 ; SET LR5 CR0 ;;
height_loop:
SET LR4 CR0 ; SET LR6 LR1 ;;
width_loop:
SET LR8 CR0 ; SET LR9 LR6 ; SET LR10 CR0 ;;
SET LR7 CR0 ; SET LR14 LR5 ;;
SET LR13 LR4 ;;
INC.MODP2 LR13 CR0 1 ;;
BEQ LR13 CR0 gather ;;
ADD LR14 LR14 {{ cr.height }} ;;
gather:
LD.MULT R0 LR9 {{ cr.in0 }} ;;
INC LR8 1 ; ADD LR9 LR9 {{ cr.stride }} ;;
BEQ LR8 {{ cr.channels }} gather_last ;;
MULT.EE LR14 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.one }}.L ;;
INC.MODP2 LR7 CR1 7 ;;
BNE LR7 CR0 gather ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
INC LR10 1 ; SET LR7 CR0 ;;
BEQ CR0 CR0 gather ;;
gather_last:
MULT.EE LR14 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.one }}.L ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
INC LR10 1 ; SET LR7 CR0 ;;
LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
INC LR7 1 ;;
BEQ LR7 LR10 reduce_single ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
reduce_loop:
LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
INC LR7 1 ;;
BEQ LR7 LR10 reduce_last ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; AGG.SUM LR0 CR15.L ;;
BEQ CR0 CR0 reduce_loop ;;
reduce_last:
MULT.RC.VS LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_out0 }}.L ; AGG.SUM LR0 {{ cr.tail }}.L ; ACTIVATE.QUANTIZE rsqrt {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
BEQ CR0 CR0 finish ;;
reduce_single:
MULT.RC.VS LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_out0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.tail }}.L ; ACTIVATE.QUANTIZE rsqrt {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
finish:
LD.MULT R0 LR10 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE reciprocal {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
INC LR2 1 ; INC LR4 1 ;;
SET LR13 LR4 ;;
INC.MODP2 LR13 CR0 1 ;;
BNE LR13 CR0 width_next ;;
INC LR6 1 ;;
width_next:
BLT.S LR4 {{ cr.width }} width_loop ;;
INC LR3 1 ; INC LR5 1 ;;
BLT.S LR3 {{ cr.height }} height_loop ;;
BEQ CR0 CR0 next_batch ;;
next_batch:
SUB LR1 LR9 LR6 ;;
ADD LR1 LR1 LR11 ; INC LR15 1 ;;
BLT.S LR15 {{ cr.batch }} batch_loop ;;
HALT ;;
