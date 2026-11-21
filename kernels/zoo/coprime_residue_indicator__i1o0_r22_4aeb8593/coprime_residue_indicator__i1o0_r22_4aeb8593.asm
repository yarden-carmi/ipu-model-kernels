SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ;;
SET LR4 CR0 ;;
INC LR4 128 ;;
row:
LD.MULT R1 LR1 {{ cr.ramp }} ;;
SET LR2 CR0 ;;
chunk:
LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
MULT.VE LR4 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
MULT.VE LR4 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.ADD.FIRST ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
LD.MULT R0 LR0 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB.FIRST ;;
LD.MULT R0 LR3 {{ cr.out0 }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
LD.MULT R0 LR0 {{ cr.one }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_one }}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR3 1 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.chunks }} chunk ;;
INC LR1 1 ;;
BLT.S LR1 {{ cr.vocab }} row ;;
HALT ;;
