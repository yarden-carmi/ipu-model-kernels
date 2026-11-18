SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
SET LR6 CR0 ;;
SET LR4 CR0 ;;
INC LR4 128 ;;
vocab_loop:
SET LR2 CR0 ;;
token_loop:
LD.MULT R0 LR2 {{ cr.in0 }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% macro indices(op) %}
ADD LR7 LR6 CR0 ;;
{% for part in range(3) %}
LD.MULT R1 LR7 {{ cr.indices }} ;;
MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_indices }}.L ; {{ op }} ; INC LR7 1 ;;
{% endfor %}
{% endmacro %}
{{ indices('ACC.SUB') }}
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST ;;
{{ indices('ACC.ADD') }}
SET LR5 CR1 ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR5 ;;
LD.MULT R0 LR0 {{ cr.ones }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
LD.MULT R0 LR0 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
LD.MULT R0 LR5 {{ cr.tmp }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR3 1 ; INC LR2 1 ;;
BLT.S LR2 {{ cr.chunks }} token_loop ;;
INC LR1 1 ;;
INC LR6 3 ;;
BLT.S LR1 {{ cr.vocab }} vocab_loop ;;
HALT ;;
