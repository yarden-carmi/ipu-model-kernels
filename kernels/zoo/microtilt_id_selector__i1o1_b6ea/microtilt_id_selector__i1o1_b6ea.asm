{# Fixed address selector. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR4 CR0 ;;
LD.MULT R0 LR0 {{ cr.in0 }} ;;
LD.MULT R1 LR0 {{ cr.in0 }} ;;
row:
SET LR6 CR0 ;;
INC LR6 128 ;;
BNE LR1 LR6 ready ;;
SET LR6 CR1 ;;
LD.MULT R0 LR6 {{ cr.in0 }} ;;
SET LR1 CR0 ;;
ready:
SET LR3 CR0 ;;
chunk:
MULT.EE LR1 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
LD.MULT R1 LR3 {{ cr.ramp }} ;;
SET LR5 CR0 ;;
INC LR5 128 ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_ramp }}.L ; ACC.SUB ;;
LD.MULT R1 LR3 {{ cr.high }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_high }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE relu {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_high }}.L ; ACC.ADD.FIRST ;;
LD.MULT R1 LR3 {{ cr.ramp }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_ramp }}.L ; ACC.ADD ;;
MULT.EE LR1 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE relu {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
LD.MULT R1 LR0 {{ cr.tmp }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
LD.MULT R1 LR2 {{ cr.out0 }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE relu {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
INC LR2 1 ; INC LR3 1 ;;
BLT.S LR3 {{ cr.chunks }} chunk ;;
INC LR1 1 ;;
INC LR4 1 ;;
BLT.S LR4 {{ cr.tokens }} row ;;
HALT ;;
