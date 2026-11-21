{# Selector via positive and negative distances. #}
{% macro distance(sign) %}
MULT.EE LR1 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST ;;
ADD LR7 LR3 LR15 ;;
LD.MULT R1 LR7 {{ cr.hi }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_hi }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ;;
LD.MULT R1 LR3 {{ cr.hi }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_hi }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ;;
LD.MULT R1 LR0 {{ cr.lo }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_lo }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }} ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR4 CR0 ; SET LR6 CR0 ;;
SET LR5 CR0 ;;
INC LR5 128 ;;
token:
LD.MULT R0 LR2 {{ cr.in0 }} ;;
SET LR3 CR0 ;;
chunk:
{{ distance(1) }}
ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.pos }} LR0 ;;
{{ distance(-1) }}
ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.neg }} LR0 ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
LD.MULT R1 LR0 {{ cr.pos }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
LD.MULT R1 LR0 {{ cr.neg }} ;;
MULT.VE LR5 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
MULT.VE LR5 CR0 0 LR0 {{ cr.full }}.L {{ cr.qf_out0 }}.L ; ACC.MAX ;;
INC LR3 1 ;;
BEQ LR3 LR15 last ;;
ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
INC LR4 1 ;;
BEQ CR0 CR0 chunk ;;
last:
ACTIVATE.QUANTIZE identity {{ cr.lastds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
INC LR4 1 ;;
INC LR2 1 ;;
INC LR6 1 ;;
BLT.S LR6 LR14 token ;;
HALT ;;
