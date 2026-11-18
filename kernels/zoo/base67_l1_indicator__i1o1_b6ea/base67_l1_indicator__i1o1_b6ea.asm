{# Equality by squared integer distance. #}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR7 CR0 ;;
token_loop:
LD.MULT R0 LR1 {{ cr.in0 }} ;;
SET LR4 CR0 ;;
chunk_loop:
MULT.EE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
SET LR5 LR4 ;;
{% macro subtract_digit() %}
LD.MULT R1 LR5 {{ cr.digits }} ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.SUB ;;
{% endmacro %}
{{ subtract_digit() }}
ADD LR5 LR5 {{ cr.chunks }} ;;
{{ subtract_digit() }}
ADD LR5 LR5 {{ cr.chunks }} ;;
{{ subtract_digit() }}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_diff }}.L {{ cr.diff }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.diff }} LR0 ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_diff }}.L ; ACC.SUB.FIRST ;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD ;;
INC LR4 1 ;;
BLT.S LR4 {{ cr.chunks }} full_store ;;
ACTIVATE.QUANTIZE relu {{ cr.last_ds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
BEQ LR0 CR0 end_chunk ;;
full_store:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
end_chunk:
INC LR3 1 ;;
BLT.S LR4 {{ cr.chunks }} chunk_loop ;;
INC LR2 1 ; INC LR7 1 ;;
BLT.S LR2 {{ lr.offset128 }} next_token ;;
SET LR2 CR0 ; INC LR1 1 ;;
next_token:
BLT.S LR7 {{ cr.tokens }} token_loop ;;
HALT ;;
