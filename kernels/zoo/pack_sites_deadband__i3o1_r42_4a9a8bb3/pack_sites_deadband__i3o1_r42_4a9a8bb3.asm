SET LR0 CR0 ; SET LR8 CR0 ; SET LR9 CR0;;
SET LR10 CR0;;
batch:
SET LR11 CR0;;
height:
SET LR12 CR0;;
width:
SET LR2 CR0 ; SET LR3 CR0 ; SET LR4 CR0;;
SET LR5 CR0;;
SET LR6 LR10 ; SET LR7 CR0;;
MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
channel:
LD.MULT R0 LR6 {{ cr.in0 }};;
MULT.EE LR12 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.RESHAPE LRD2 LRD4 7;;
ADDBI LRD4 1 ; ADD LR6 LR6 {{ cr.channel_stride }} ; INC LR7 1;;
BLT.S LR7 {{ cr.cin }} channel;;
ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.channel_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR8;;
INC LR8 1 ; INC LR12 1;;
BLT.S LR12 {{ cr.in0_d3 }} width;;
INC LR10 1 ; INC LR11 1;;
BLT.S LR11 {{ cr.in0_d2 }} height;;
INC LR9 1;;
BLT.S LR9 {{ cr.in0_d0 }} batch;;
HALT;;
