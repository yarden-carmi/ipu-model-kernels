{# Repeat the first table row, preserving channel tiles along lanes. #}
SET LR0 CR0 ; SET LR1 CR0 ;;
chunk_loop:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf }}.L ; ACC.ADD.FIRST ;;
SET LR2 LR1 ; SET LR3 CR0 ;;
row_loop:
ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf }}.L {{ cr.out0 }} LR2 ;;
ADD LR2 LR2 {{ cr.chunks }} ; INC LR3 1 ;;
BLT.S LR3 {{ cr.total_rows }} row_loop ;;
INC LR1 1 ;;
BLT.S LR1 {{ cr.chunks }} chunk_loop ;;
HALT ;;
