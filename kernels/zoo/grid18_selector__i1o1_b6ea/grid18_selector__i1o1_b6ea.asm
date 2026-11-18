{# Fixed-address vocabulary sweep; no ID participates in addressing. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR4 CR0 ; SET LR5 CR0 ;;
INC LR6 128 ;;
token:
LD.MULT R0 LR2 {{ cr.in0 }} ;;
SET LR3 CR0 ;;
chunk:
LD.MULT R1 LR3 {{ cr.indices }} ;;
MULT.EE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_indices }}.L ; ACC.ADD ;;
LD.MULT R1 LR0 {{ cr.low }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_low }}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
LD.MULT R1 LR0 {{ cr.tmp }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB.FIRST ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.MAX ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
LD.MULT R1 LR0 {{ cr.tmp }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB.FIRST ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD ;;
INC LR3 1 ;;
BLT.S LR3 {{ lr.chunks }} full ;;
ACTIVATE.QUANTIZE relu {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
BEQ LR0 CR0 store ;;
full:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
store:
INC LR4 1 ;;
BLT.S LR3 {{ lr.chunks }} chunk ;;
INC LR5 1 ; INC.MODP2 LR1 CR1 7 ;;
BNE LR1 CR0 next ;;
INC LR2 1 ;;
next:
BLT.S LR5 {{ lr.tokens }} token ;;
HALT ;;
