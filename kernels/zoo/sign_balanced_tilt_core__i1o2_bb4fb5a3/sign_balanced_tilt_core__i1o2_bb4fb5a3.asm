{#- Quantized small tilt: perturbation is below one output grid step. -#}
SET LR0 CR0 ; SET LR1 CR0 ;;
row_loop:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
INC LR1 1 ;;
BLT.S LR1 {{ cr.rows }} row_loop ;;
HALT ;;
