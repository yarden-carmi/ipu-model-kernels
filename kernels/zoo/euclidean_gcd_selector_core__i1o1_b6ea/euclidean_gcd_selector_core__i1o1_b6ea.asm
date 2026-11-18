SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
SET LR6 CR1 ;;
SET LR7 CR1 ;;
INC LR7 1 ;;
SET LR9 CR1 ;;
INC LR9 2 ;;
LD.MULT R0 LR0 CR2 ;;
LD.MULT R1 LR6 CR2 ;;
LD.MULT.CYCLIC LR0 CR14 LR8 ;;
token:
SET LR2 CR0 ;;
chunk:
LD.MULT R1 LR6 CR2 ;;
{% macro sub(base) %}
LD.MULT.CYCLIC LR2 {{ base }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
{% endmacro %}
{% macro step(upper, dest) %}
LD.MULT R1 LR6 CR2 ;;
MULT.EE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
{{ sub('CR4') }}
{{ sub('CR9') }}
{{ sub('CR5') }}
{% if upper %}
MULT.RC.VE LR8 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD ;;
{% else %}
ADD LR10 LR2 LR6 ;;
LD.MULT.CYCLIC LR10 CR10 LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.wide }}.L ; ACC.SUB ;;
{% endif %}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.wide }}.L CR6 LR6 ;;
LD.MULT R1 LR0 CR10 ;;
LD.MULT.CYCLIC LR6 CR6 LR0 ;;
MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.wide }}.L ; ACC.ADD.FIRST ;;
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.wide }}.L CR6 LR6 ;;
LD.MULT.CYCLIC LR6 CR6 LR0 ;;
MULT.RC.VE LR8 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.wide }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.wide }}.L CR6 LR6 ;;
LD.MULT.CYCLIC LR6 CR6 LR0 ;;
MULT.RC.VE LR8 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.wide }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L CR6 {{ dest }} ;;
{% endmacro %}
{{ step(false, 'LR7') }}
{{ step(true, 'LR9') }}
LD.MULT.CYCLIC LR9 CR6 LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
LD.MULT.CYCLIC LR7 CR6 LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
INC LR2 1 ;;
BEQ LR2 CR11 tail ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L CR3 LR3 ;;
INC LR3 1 ;;
BLT.S LR2 CR11 chunk ;;
tail:
ACTIVATE.QUANTIZE relu CR15.H {{ cr.qf_out0 }}.L CR3 LR3 ;;
INC LR3 1 ;;
INC LR1 1 ;;
BLT.S LR1 CR12 token ;;
HALT ;;
