{# Dense vocabulary equality via a squared integer difference. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
SET LR6 {{ cr.idx }} ;;
token:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
SET LR3 CR0 ;;
chunk:
MULT.EE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
LD.MULT R1 LR3 {{ cr.ramp }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_diff }}.L {{ cr.diff }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.diff }} LR0 ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_diff }}.L ; ACC.SUB.FIRST ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD ;;
BEQ LR3 LR13 tail ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
BEQ LR0 LR0 stored ;;
tail:
ACTIVATE.QUANTIZE relu {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
stored:
INC LR3 1 ; INC LR4 1 ;;
BLT.S LR3 {{ cr.chunks }} chunk ;;
INC LR2 1 ; INC LR5 1 ;;
BLT.S LR2 LR6 next_token ;;
SET LR2 CR0 ; INC LR1 1 ;;
next_token:
BLT.S LR5 LR14 token ;;
HALT ;;
