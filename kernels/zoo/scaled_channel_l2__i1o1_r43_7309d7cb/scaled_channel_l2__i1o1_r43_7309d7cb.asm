 SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
site:
 SET LR3 CR0 ;;
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM.FIRST LR0 {% if channels <= 128 %}{{ cr.ds_tail }}.L{% else %}CR15.L{% endif %} ; INC LR1 1 ; INC LR3 1 ;;
 BEQ LR3 {{ cr.chunks }} finish_sum ;;
chunk:
 LD.MULT.CYCLIC LR1 {{ cr.in0 }} LR0 ;;
 INC LR3 1 ;;
 BEQ LR3 {{ cr.chunks }} last_chunk ;;
 MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 CR15.L ; INC LR1 1 ;;
 B chunk ;;
last_chunk:
 MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; AGG.SUM LR0 {{ cr.ds_tail }}.L ; INC LR1 1 ;;
finish_sum:
 ACTIVATE.QUANTIZE rsqrt {{ cr.ds_one }}.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
 LD.MULT R0 LR0 {{ cr.tmp }} ;;
 MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
 ACTIVATE.QUANTIZE reciprocal {{ cr.ds_one }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
 INC LR2 1 ;;
 BLT.S LR2 {{ cr.sites }} site ;;
 HALT ;;
