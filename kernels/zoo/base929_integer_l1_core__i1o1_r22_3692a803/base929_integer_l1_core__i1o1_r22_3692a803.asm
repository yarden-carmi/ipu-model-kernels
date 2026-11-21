{# Integer equality via squared distance and exact radix-32 index pieces. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR4 CR0 ; SET LR5 CR0 ; SET LR3 CR0 ;;
INC LR3 128 ;;
token_loop:
LD.MULT R1 LR2 {{ cr.in0 }} ;;
SET LR6 CR0 ; SET LR7 CR0 ;;
chunk_loop:
MULT.EE LR3 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% macro digit() %}
LD.MULT R0 LR7 {{ cr.digits }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.SUB ;;
ADD LR7 LR7 {{ cr.chunks }} ;;
{% endmacro %}
{{ digit() }}
{{ digit() }}
{{ digit() }}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.sq_qf }}.L {{ cr.delta }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.delta }} LR0 ;;
LD.MULT R0 LR0 {{ cr.ones }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.sq_qf }}.L ; ACC.SUB ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.MAX ;;
INC LR6 1 ;;
BLT.S LR6 {{ cr.chunks }} full_store ;;
ACTIVATE.QUANTIZE identity {{ cr.last_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
BEQ CR0 CR0 next_token ;;
full_store:
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4 ;;
INC LR4 1 ; SET LR7 LR6 ;;
BEQ CR0 CR0 chunk_loop ;;
next_token:
INC LR4 1 ; INC LR1 1 ;;
INC.MODP2 LR5 CR1 7 ;;
SET LR3 LR5 ;;
INC LR3 128 ;;
BNE LR5 CR0 same_input ;;
INC LR2 1 ;;
same_input:
BLT.S LR1 {{ cr.tokens }} token_loop ;;
HALT ;;
