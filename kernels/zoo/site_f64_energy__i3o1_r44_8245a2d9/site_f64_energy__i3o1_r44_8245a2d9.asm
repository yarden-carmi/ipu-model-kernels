SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR15 CR0 ;;
batch_loop:
SET LR11 LR1 ; SET LR3 CR0 ; SET LR5 CR0 ;;
height_loop:
SET LR4 CR0 ; SET LR6 LR1 ;;
width_loop:
SET LR8 CR0 ; SET LR9 LR6 ; SET LR10 CR0 ;;
SET LR7 CR0 ; ADD LR14 LR5 LR4 ;;
gather:
LD.MULT R0 LR9 {{ cr.in0 }} ;;
INC LR8 1 ; ADD LR9 LR9 {{ cr.stride }} ;;
BEQ LR8 {{ cr.channels }} gather_last ;;
MULT.EE LR14 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.one }}.L ;;
INC.MODP2 LR7 CR1 7 ;;
BNE LR7 CR0 gather ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR10 ;;
INC LR10 1 ; SET LR7 CR0 ;;
BEQ CR0 CR0 gather ;;
gather_last:
MULT.EE LR14 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR7 {{ cr.one }}.L ; ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_in0 }}.L {{ cr.tmp }} LR10 ;;
INC LR10 1 ; SET LR7 CR0 ;;
LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
INC LR7 1 ;;
BEQ LR7 LR10 reduce_single ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
reduce_loop:
LD.MULT.CYCLIC LR7 {{ cr.tmp }} LR0 ;;
INC LR7 1 ;;
BEQ LR7 LR10 reduce_last ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 CR15.L ;;
BEQ CR0 CR0 reduce_loop ;;
reduce_last:
MULT.RC.VS LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.tail }}.L ; ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
BEQ CR0 CR0 finish ;;
reduce_single:
MULT.RC.VS LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.tail }}.L ; ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR10 ;;
finish:
SET LR12 LR10 ;;
INC LR12 1 ;;
LD.MULT R0 LR10 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE rsqrt {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR12 ;;
SET LR13 LR12 ;;
INC LR13 1 ;;
MULT.VE LR0 CR0 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR13 ;;
SET LR7 LR13 ;;
INC LR7 1 ;;
MULT.VE LR0 CR0 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR7 ;;
LD.MULT.CYCLIC LR13 {{ cr.tmp }} LR0 ;;
LD.MULT R0 LR13 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE rsqrt {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR13 ;;
LD.MULT R0 LR13 {{ cr.tmp }} ;;
MULT.RC.VV LR0 R0 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE identity {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR13 ;;
LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
LD.MULT R0 LR12 {{ cr.tmp }} ;;
MULT.RC.VV LR0 R0 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
LD.MULT R0 LR13 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
LD.MULT R0 LR7 {{ cr.tmp }} ;;
SET LR8 CR0 ; SET LR13 CR0 ; SET LR7 CR0 ;;
root_loop:
INC LR7 1 ;;
ADD LR13 LR13 LR7 ; INC LR7 1 ; INC LR8 1 ;;
BLT.S LR13 {{ cr.channels }} root_loop ;;
SET LR13 LR8 ; SET LR8 CR0 ;;
tiny_loop:
MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
INC LR8 1 ;;
BLT.S LR8 LR13 tiny_loop ;;
ACTIVATE.QUANTIZE relu {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
INC LR2 1 ; INC LR4 1 ;;
BLT.S LR4 {{ cr.width }} width_loop ;;
INC LR3 1 ; ADD LR5 LR5 {{ cr.width }} ;;
BEQ LR5 {{ cr.chunks }} next_chunk ;;
BLT.S LR3 {{ cr.height }} height_loop ;;
BEQ CR0 CR0 next_batch ;;
next_chunk:
SET LR5 CR0 ; INC LR1 1 ;;
BLT.S LR3 {{ cr.height }} height_loop ;;
next_batch:
SUB LR1 LR9 LR6 ;;
ADD LR1 LR1 LR11 ; INC LR15 1 ;;
BLT.S LR15 {{ cr.batch }} batch_loop ;;
HALT ;;
