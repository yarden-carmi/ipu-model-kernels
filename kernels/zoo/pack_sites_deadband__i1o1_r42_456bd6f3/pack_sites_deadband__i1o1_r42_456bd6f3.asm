{# Both layouts already enumerate sites in N,H,W order, with channels in lanes. #}
SET LR0 CR0 ; SET LR1 CR0;;
row:
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.channel_ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.channel_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1;;
INC LR1 1;;
BLT.S LR1 {{ cr.out0_d0 }} row;;
HALT;;
