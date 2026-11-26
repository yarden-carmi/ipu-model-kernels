{#- Pack NCHW into a logical site-by-channel matrix.
    Site lanes preserve the packed spatial rows; only the batch/channel
    row traversal changes, so no lane transpose is needed. -#}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0;;
SET LR3 CR0;;
channel:
SET LR4 LR3 ; SET LR5 CR0;;
batch:
SET LR6 LR4 ; ADD LR7 LR4 {{ cr.site_rows }};;
row:
LD.MULT R0 LR6 {{ cr.in0 }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1;;
INC LR6 1 ; INC LR1 1;;
BLT.S LR6 LR7 row;;
ADD LR4 LR4 {{ cr.batch_stride }} ; INC LR5 1;;
BLT.S LR5 {{ cr.in0_d0 }} batch;;
ADD LR3 LR3 {{ cr.site_rows }} ; INC LR2 1;;
BLT.S LR2 {{ cr.cin }} channel;;
HALT;;
