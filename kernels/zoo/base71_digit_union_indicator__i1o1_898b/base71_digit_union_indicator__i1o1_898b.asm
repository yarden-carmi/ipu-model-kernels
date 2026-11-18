{% macro digit(scale, first) %}
LD.MULT.CYCLIC LR4 {{ cr.digits }} LR0 ;;
MULT.RC.VE LR0 {{ scale }} 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.ADD{{ '.FIRST' if first else '' }} ; ADD LR4 LR4 {{ cr.chunks }} ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ;;
SET LR9 CR0 ;;
INC LR9 128 ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
token_loop:
LD.MULT R0 LR2 {{ cr.in0 }} ;;
SET LR5 CR0 ;;
chunk_loop:
SET LR4 LR5 ;;
{{ digit('CR1', true) }}
{{ digit('CR1', false) }}
{{ digit('CR1', false) }}
MULT.EE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qs }}.L {{ cr.tmp }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qs }}.L ; ACC.SUB.FIRST ;;
MULT.EE LR9 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD ;;
INC LR5 1 ;;
BLT.S LR5 {{ cr.chunks }} full ;;
ACTIVATE.QUANTIZE relu {{ cr.lastds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
BEQ CR0 CR0 after_store ;;
full:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
after_store:
INC LR3 1 ;;
BLT.S LR5 {{ cr.chunks }} chunk_loop ;;
INC.MODP2 LR1 CR1 7 ;;
INC LR8 1 ;;
BNE LR1 CR0 same_row ;;
INC LR2 1 ;;
same_row:
BLT.S LR8 {{ cr.tokens }} token_loop ;;
HALT ;;
