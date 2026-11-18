SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ;;
token:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
SET LR2 CR0 ;;
chunk:
MULT.EE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
SET LR4 LR2 ;;
{% for i in range(3) %}
LD.MULT R1 LR4 {{ cr.ramp }} ;;
SET LR5 CR0 ;;
INC LR5 128 ;;
MULT.VE LR5 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.SUB ;;
ADD LR4 LR4 {{ cr.chunks }} ;;
{% endfor %}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.VE LR5 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB ;;
INC LR2 1 ;;
BNE LR2 {{ cr.chunks }} full ;;
ACTIVATE.QUANTIZE relu {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
BEQ LR2 {{ cr.chunks }} next ;;
full:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
next:
INC LR3 1 ;;
BLT.S LR2 {{ cr.chunks }} chunk ;;
INC LR1 1 ;;
BLT.S LR1 {{ cr.tokens }} token ;;
HALT ;;
