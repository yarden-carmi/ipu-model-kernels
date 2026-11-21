SET LR0 CR0;;
SET LR1 CR0;;
SET LR3 CR0;;
token:
SET LR2 CR0;;
chunk:
LD.MULT R0 LR2 {{ cr.table }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L;;
ACC.ADD.FIRST;;
ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf }}.L {{ cr.out0 }} LR1;;
ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf }}.L {{ cr.out1 }} LR1;;
INC LR1 1;;
INC LR2 1;;
BNE LR2 {{ cr.chunks }} chunk;;
INC LR3 1;;
BNE LR3 {{ cr.s4_tokens }} token;;
HALT;;
