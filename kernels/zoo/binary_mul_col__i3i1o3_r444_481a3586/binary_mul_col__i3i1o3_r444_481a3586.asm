{% macro product() %}
 MULT.RC.VE LR0 LR4 0 LR0 {{ cr.valid }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ; ACTIVATE.QUANTIZE {{ act_out0 | default('identity') }} {{ cr.valid }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR6
{% endmacro %}
 SET LR0 CR0 ; SET LR2 CR0 ; SET LR3 CR0 ;;
 SET LR4 CR0 ;;
scale_block:
 LD.MULT R0 LR3 {{ cr.in1 }} ;;
 INC LR3 1 ;;
channel:
 SET LR5 CR0 ; SET LR6 LR2 ; SET LR7 LR2 ;;
 LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; BEQ {{ cr.last_y }} CR0 last ;;
spatial:
 ADD LR7 LR7 {{ cr.inner }} ; INC LR5 1 ;;
 LD.MULT.CYCLIC LR7 {{ cr.in0 }} LR0 ; {{ product() }} ;;
 ADD LR6 LR6 {{ cr.inner }} ; BLT.S LR5 {{ cr.last_y }} spatial ;;
last:
 {{ product() }} ;;
 INC LR2 1 ; INC.MODP2 LR4 CR1 7 ;;
 BEQ LR2 {{ cr.inner }} done ;;
 BEQ LR4 CR0 scale_block ;;
 B channel ;;
done:
 HALT ;;
