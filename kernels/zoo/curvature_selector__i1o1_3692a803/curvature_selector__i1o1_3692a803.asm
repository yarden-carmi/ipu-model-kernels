{% macro step(which) %}
SET LR6 CR0 ;;
INC LR6 2 ;;
LD.MULT.CYCLIC LR6 {{ cr.steps }} LR0 ;;
LD.MULT R1 LR0 {{ cr.big }} ;;
MULT.RC.VV LR0 R1 0 LR0 {{ cr.ds }}.L {{ cr.qf_big }}.L ; ACC.ADD.FIRST ;;
{% for digit in range(4) %}
SET LR6 LR4 ;;
{% for n in range(which * 4 + digit) %}
ADD LR6 LR6 LR10 ;;
{% endfor %}
LD.MULT R1 LR6 {{ cr.thresholds }} ;;
MULT.VE LR7 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_thresholds }}.L ; ACC.{{ 'ADD' if digit == 3 else 'SUB' }} ;;
{% endfor %}
SET LR6 CR{{ which }} ;;
ACTIVATE.QUANTIZE relu6 {{ cr.ds }}.L {{ cr.qf_steps }}.L {{ cr.steps }} LR6 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR4 CR0 ;;
SET LR5 CR0 ;;
SET LR7 CR0 ;;
INC LR7 128 ;;
token:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
MULT.EE LR3 CR1 0 LR0 {{ cr.ds }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
SET LR6 CR0 ;;
INC LR6 2 ;;
ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_steps }}.L {{ cr.steps }} LR6 ;;
SET LR4 CR0 ;;
chunk:
{{ step(0) }}
{{ step(1) }}
LD.MULT R1 LR0 {{ cr.sixth }} ;;
LD.MULT.CYCLIC LR0 {{ cr.steps }} LR0 ;;
MULT.RC.VV LR0 R1 0 LR0 {{ cr.ds }}.L {{ cr.qf_steps }}.L ; ACC.ADD.FIRST ;;
SET LR6 CR1 ;;
LD.MULT.CYCLIC LR6 {{ cr.steps }} LR0 ;;
MULT.RC.VV LR0 R1 0 LR0 {{ cr.ds }}.L {{ cr.qf_steps }}.L ; ACC.SUB ;;
INC LR4 1 ;;
BLT.S LR4 LR10 full ;;
ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
BEQ CR0 CR0 endchunk ;;
full:
ACTIVATE.QUANTIZE identity {{ cr.ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2 ;;
endchunk:
INC LR2 1 ;;
BLT.S LR4 LR10 chunk ;;
INC LR3 1 ;;
INC LR5 1 ;;
SET LR6 CR0 ;;
INC LR6 128 ;;
BNE LR3 LR6 nocarry ;;
SET LR3 CR0 ; INC LR1 1 ;;
nocarry:
BLT.S LR5 LR8 token ;;
HALT ;;
