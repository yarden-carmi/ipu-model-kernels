{# Broadcast the offline vocabulary mean, preserving channel-lane layout. #}
SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
row_loop:
SET LR1 CR0 ;;
channel_loop:
LD.MULT R0 LR1 {{ cr.mean }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
INC LR1 1 ; INC LR2 1 ;;
BNE LR1 {{ cr.blocks }} channel_loop ;;
INC LR3 1 ;;
BNE LR3 {{ cr.rows }} row_loop ;;
HALT ;;
