SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
row:
SET LR4 CR0 ;;
pixel:
SET LR3 {{ cr.chunks }} ;;
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
INC LR1 1 ; DEC LR3 1 ;;
BEQ LR3 CR0 single ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
more:
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
INC LR1 1 ; DEC LR3 1 ;;
BEQ LR3 CR0 last ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 CR15.L ;;
BEQ CR0 CR0 more ;;
last:
MULT.RC.VS LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.tail }}.L ;;
BEQ CR0 CR0 next ;;
single:
MULT.RC.VS LR0 0 LR0 {{ cr.tail }}.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.tail }}.L ;;
next:
ACTIVATE.QUANTIZE rsqrt {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
LD.MULT R0 LR0 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE reciprocal {{ cr.one }}.L {{ cr.qf_out0 }}.L {{ cr.values }} LR4 ;;
INC LR4 1 ;;
BLT.S LR4 {{ cr.active_count }} pixel ;;
SET LR4 CR0 ;;
gather:
LD.MULT R0 LR4 {{ cr.values }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.one }}.L {{ cr.qf_out0 }}.L ; AGG.SUM.FIRST LR4 {{ cr.one }}.L ;;
INC LR4 1 ;;
BLT.S LR4 {{ cr.active_count }} gather ;;
ACTIVATE.QUANTIZE identity {{ cr.active }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
INC LR2 1 ;;
BLT.S LR2 {{ cr.rows }} row ;;
HALT ;;
