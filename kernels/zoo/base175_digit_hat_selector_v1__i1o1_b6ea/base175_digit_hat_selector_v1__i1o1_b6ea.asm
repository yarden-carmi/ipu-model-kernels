{# Exact equality: split ramp subtraction, then relu(1 - difference squared). #}
{% macro row(ds) %}
LD.MULT.CYCLIC LR2 {{ cr.hi }} LR0 ;;
MULT.EE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_hi }}.L ; ACC.SUB ;;
LD.MULT.CYCLIC LR2 {{ cr.lo }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_lo }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.ones }} LR14 ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR14 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu {{ ds }} {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR2 1 ; INC LR3 1 ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
LD.MULT R0 LR0 {{ cr.in0 }} ;;
SET LR5 CR1 ;;
LD.MULT R1 LR5 {{ cr.in0 }} ;;
token_loop:
SET LR2 CR0 ;;
chunk_loop:
{{ row('CR15.L') }}
ADD LR5 LR2 CR1 ;;
BLT.S LR5 {{ cr.chunks }} chunk_loop ;;
{{ row(cr.lastds ~ '.L') }}
INC LR1 1 ;;
BLT.S LR1 {{ cr.tokens }} token_loop ;;
HALT ;;
