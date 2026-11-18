 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
pos:
 SET LR3 CR0 ; SET LR4 CR0 ;;
block:
 LD.MULT R0 LR4 {{cr.weights}} ;;
 MULT.VE LR15 CR1 0 LR15 {{cr.full}}.L {{cr.qf_weights}}.L ; ACC.ADD.FIRST ; INC LR4 1 ;;
 SET LR5 LR1 ; SET LR6 CR0 ;;
tap:
 LD.MULT R0 LR5 {{cr.in0}} ;;
 LD.MULT.CYCLIC LR4 {{cr.weights}} LR15 ;;
 MULT.RC.VE LR15 LR15 0 LR15 {{cr.full}}.L {{cr.qf_in0}}.L ; ACC.ADD ; INC LR4 1 ; INC LR5 1 ;;
 INC LR6 1 ;;
 BLT.S LR6 {{cr.taps}} tap ;;
 ACTIVATE.QUANTIZE identity {{cr.full}}.L {{cr.qf_out0}}.L {{cr.out0}} LR2 ;;
 INC LR2 1 ; INC LR3 1 ;;
 BLT.S LR3 {{cr.blocks}} block ;;
 INC LR0 1 ;;
 INC LR1 {{stride}} ;;
 BLT.S LR0 {{cr.positions}} pos ;;
 HALT ;;
