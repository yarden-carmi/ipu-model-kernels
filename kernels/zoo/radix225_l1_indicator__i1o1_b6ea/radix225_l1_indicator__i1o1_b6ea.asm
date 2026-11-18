{# Equality of integer IDs via an exact split compile-time ramp. #}
{% macro difference(sign) %}
LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.EE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
LD.MULT R1 LR5 {{ cr.ramp }} ;;
MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ;;
INC LR5 1 ;;
LD.MULT R1 LR5 {{ cr.ramp }} ;;
MULT.VE LR7 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ;;
DEC LR5 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR4 CR0 ; SET LR6 CR0 ; SET LR7 CR0 ;;
INC LR7 128 ;;
token:
SET LR3 CR0 ; SET LR5 CR0 ;;
chunk:
{{ difference(1) }}
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
{{ difference(-1) }}
SET LR8 CR1 ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR8 ;;
LD.MULT R0 LR0 {{ cr.ones }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
LD.MULT R0 LR0 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
LD.MULT R0 LR8 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
INC LR3 1 ;;
BLT.S LR3 {{ cr.chunks }} full ;;
ACTIVATE.QUANTIZE relu {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
BEQ LR0 CR0 stored ;;
full:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
stored:
INC LR4 1 ; INC LR5 2 ;;
BLT.S LR3 {{ cr.chunks }} chunk ;;
INC LR6 1 ; INC.MODP2 LR1 CR1 7 ;;
BNE LR1 CR0 next ;;
INC LR2 1 ;;
next:
BLT.S LR6 {{ cr.tokens }} token ;;
HALT ;;
