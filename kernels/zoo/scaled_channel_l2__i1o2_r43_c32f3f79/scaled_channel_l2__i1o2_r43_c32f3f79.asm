 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
 SET LR4 CR0 ; SET LR5 CR0 ;;
site:
 SET LR3 CR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 INC LR1 1 ; INC LR3 1 ;;
 BEQ LR3 {{ cr.chunks }} first_last ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 CR15.L ;;
chunk:
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 INC LR1 1 ; INC LR3 1 ;;
 BEQ LR3 {{ cr.chunks }} last ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 CR15.L ;;
 B chunk ;;
first_last:
 MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 {{ cr.ds_tail }}.L ;;
 B next_site ;;
last:
 MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.ds_tail }}.L ;;
next_site:
 ACTIVATE.QUANTIZE rsqrt {{ cr.ds_one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE reciprocal {{ cr.ds_one }}.L {{ cr.qf_out0 }}.L {{ cr.values }} LR4 ;;
 INC LR2 1 ; INC LR4 1 ;;
 BEQ LR2 {{ cr.sites }} pack ;;
 BLT.S LR4 {{ cr.lanes }} site ;;
pack:
 SET LR6 CR0 ;;
pack_loop:
 LD.MULT.CYCLIC LR6 {{ cr.values }} LR0 ;;
 MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; AGG.SUM.FIRST LR6 {{ cr.ds_one }}.L ;;
 INC LR6 1 ;;
 BLT.S LR6 LR4 pack_loop ;;
 BEQ LR2 {{ cr.sites }} final_row ;;
 ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 INC LR5 1 ; SET LR4 CR0 ;;
 B site ;;
final_row:
 ACTIVATE.QUANTIZE identity {{ cr.ds_sites }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
 HALT ;;
