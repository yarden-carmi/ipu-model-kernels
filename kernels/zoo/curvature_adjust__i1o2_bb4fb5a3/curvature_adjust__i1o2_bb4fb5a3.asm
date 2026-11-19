{# Three cyclic channel taps; runtime loops over tokens and chunks. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR6 CR9 ; SET LR7 CR12 ; SET LR8 CR11 ;;
SET LR9 CR13 ;;
LD.MULT R0 LR0 {{ cr.epsilon }} ;;
token_loop:
ADD LR3 LR2 CR6 ;;
SUB LR4 LR3 CR1 ;;
chunk_loop:
ADD LR5 LR1 CR1 ;;
BLT.S LR5 LR3 next_ready ;;
SET LR5 LR2 ;;
next_ready:
LD.MULT.CYCLIC LR4 {{ cr.in0 }} LR0 ;;
LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR8 ;;
LD.MULT.CYCLIC LR5 {{ cr.in0 }} LR9 ;;
MULT.RC.VE LR8 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR8 LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
MULT.RC.VE LR8 LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
MULT.RC.VE LR6 LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
MULT.RC.VE LR7 LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
SET LR4 LR1 ; INC LR1 1 ;;
BLT.S LR1 LR3 chunk_loop ;;
SET LR2 LR3 ;;
BLT.S LR1 {{ cr.total }} token_loop ;;
HALT ;;
