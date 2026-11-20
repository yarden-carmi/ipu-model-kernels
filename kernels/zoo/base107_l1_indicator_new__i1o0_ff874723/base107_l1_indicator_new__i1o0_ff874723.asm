SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
SET LR4 {{ cr.vocab }} ; SET LR5 {{ cr.unitrow }} ;;
ADD LR6 LR4 {{ cr.vocab }} ;;
vocab_loop:
SET LR2 CR0 ;;
token_loop:
LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
LD.MULT R0 LR1 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.SUB ;;
LD.MULT R0 LR4 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.SUB ;;
LD.MULT R0 LR6 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VS LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.SUB.FIRST ;;
LD.MULT R0 LR5 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.ADD ;;
INC LR2 1 ;;
BNE LR2 {{ cr.blocks }} not_tail ;;
ACTIVATE.QUANTIZE relu {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
BEQ LR0 CR0 end_store ;;
not_tail:
ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
end_store:
INC LR3 1 ;;
BLT.S LR2 {{ cr.blocks }} token_loop ;;
INC LR1 1 ; INC LR4 1 ; INC LR6 1 ;;
BLT.S LR1 {{ cr.vocab }} vocab_loop ;;
HALT ;;
