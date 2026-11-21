{# Compare truncation intervals using saturated ramps. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR7 CR0 ; SET LR8 CR1 ;;
SET LR5 {{ cr.width }} ; SET LR10 {{ cr.width }} ;;
ADD LR11 LR10 {{ cr.width }} ;;
LD.MULT.CYCLIC LR0 {{ cr.coeff }} LR0 ;;
LD.MULT.CYCLIC LR8 {{ cr.coeff }} LR10 ;;
SET LR12 CR1 ;;
INC LR12 1 ;;
LD.MULT.CYCLIC LR12 {{ cr.coeff }} LR11 ;;
ADD LR13 LR11 {{ cr.width }} ; INC LR12 1 ;;
LD.MULT.CYCLIC LR12 {{ cr.coeff }} LR13 ;;
token:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
SET LR4 CR0 ;;
chunk:
{% macro ramp(off, dest) %}
LD.MULT R1 {{ off }} {{ cr.bounds }} ;;
MULT.RC.VE LR0 LR2 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR13 CR1 0 LR0 CR15.L {{ cr.qf_coeff }}.L ; ACC.ADD ;;
{% if dest == 'LR8' %}
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_coeff }}.L ; ACC.SUB ;;
{% endif %}
MULT.RC.VV LR0 R1 0 LR0 CR15.L {{ cr.qf_bounds }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} {{ dest }} ;;
{% endmacro %}
{{ ramp('LR4', 'LR0') }}
ADD LR6 LR4 {{ cr.chunks }} ;;
{{ ramp('LR6', 'LR8') }}
LD.MULT R1 LR0 {{ cr.tmp }} ;;
MULT.RC.VV LR10 R1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.ADD.FIRST ;;
LD.MULT R1 LR8 {{ cr.tmp }} ;;
MULT.RC.VV LR10 R1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB ;;
MULT.RC.VE LR11 CR1 0 LR0 CR15.L {{ cr.qf_coeff }}.L ; ACC.SUB ; ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR3 1 ; INC LR4 1 ;;
BLT.S LR4 {{ cr.chunks }} chunk ;;
INC LR7 1 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.width }} next ;;
SET LR2 CR0 ; INC LR1 1 ;;
next:
BLT.S LR7 {{ cr.tokens }} token ;;
HALT ;;
