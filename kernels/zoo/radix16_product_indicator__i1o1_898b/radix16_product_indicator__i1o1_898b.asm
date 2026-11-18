{# Exact integer equality via two directed differences. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ;;
SET LR7 CR0 ; SET LR6 CR1 ;;
token:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
SET LR4 CR0 ;;
chunk:
{% macro difference(sign) %}
MULT.EE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }}.FIRST ;;
SET LR5 LR4 ;;
{% for k in range(4) %}
LD.MULT.CYCLIC LR5 {{ cr.digits }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }} ;;
ADD LR5 LR5 {{ cr.chunks }} ;;
{% endfor %}
{% endmacro %}
{{ difference(1) }}
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0 ;;
{{ difference(-1) }}
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR6 ;;
LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB ;;
LD.MULT.CYCLIC LR6 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR3 1 ; INC LR4 1 ;;
BLT.S LR4 {{ cr.chunks }} chunk ;;
INC.MODP2 LR2 CR1 7 ; INC LR7 1 ;;
BNE LR2 CR0 next ;;
INC LR1 1 ;;
next:
BLT.S LR7 {{ cr.tokens }} token ;;
HALT ;;
