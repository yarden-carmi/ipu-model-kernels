SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR7 {{ cr.ones }} ; SET LR8 CR0 ;;
SET LR9 CR0 ;;
token:
SET LR3 CR0 ;;
chunk:
LD.MULT R0 LR1 {{ cr.in0 }} ; ADD LR5 LR3 {{ cr.chunks }} ; ADD LR6 LR3 {{ cr.twice }} ;;
MULT.EE LR2 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; LD.MULT R0 LR3 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.SUB ; LD.MULT R0 LR5 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.SUB ; LD.MULT R0 LR6 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
LD.MULT R0 LR7 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VS LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.SUB ;;
INC LR3 1 ;;
BLT.S LR3 {{ cr.chunks }} fullstore ;;
ACTIVATE.QUANTIZE relu {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
BEQ CR0 CR0 finishchunk ;;
fullstore:
ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8 ;;
finishchunk:
INC LR8 1 ;;
BLT.S LR3 {{ cr.chunks }} chunk ;;
INC LR9 1 ; INC.MODP2 LR2 CR1 7 ;;
BNE LR2 CR0 sameinput ;;
INC LR1 1 ;;
sameinput:
BLT.S LR9 {{ cr.tokens }} token ;;
HALT ;;
