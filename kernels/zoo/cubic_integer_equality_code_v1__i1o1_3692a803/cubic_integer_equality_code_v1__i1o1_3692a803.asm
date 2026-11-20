{# Compare exact fixed-index digits with the broadcast token. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR4 CR0 ;;
token:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
SET LR5 CR0 ;;
chunk:
MULT.EE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
LD.MULT R1 LR5 {{ cr.hi }} ;;
SET LR6 CR0 ;;
INC LR6 128 ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_hi }}.L ; ACC.SUB ;;
LD.MULT R1 LR5 {{ cr.lo }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_lo }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
LD.MULT R1 LR0 {{ cr.tmp }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB.FIRST ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.MAX ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
LD.MULT R1 LR0 {{ cr.tmp }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB.FIRST ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD ;;
INC LR5 1 ;;
BLT.S LR5 LR13 full ;;
ACTIVATE.QUANTIZE relu {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
BEQ CR0 CR0 token_end ;;
full:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR3 1 ;;
BEQ CR0 CR0 chunk ;;
token_end:
INC LR3 1 ; INC LR4 1 ; INC.MODP2 LR2 CR1 7 ;;
BNE LR2 CR0 same_row ;;
INC LR1 1 ;;
same_row:
BLT.S LR4 LR14 token ;;
HALT ;;
