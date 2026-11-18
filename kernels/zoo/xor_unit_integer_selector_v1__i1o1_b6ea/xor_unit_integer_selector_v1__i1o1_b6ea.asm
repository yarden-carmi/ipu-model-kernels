{# Equality indicator via squared difference. #}
{% macro subtract_digit() %}
LD.MULT R0 LR7 {{ cr.digits }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.SUB ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR5 CR0 ;;
SET LR8 {{ cr.ones }} ;;
token_loop:
LD.MULT R1 LR2 {{ cr.in0 }} ;;
SET LR4 LR3 ; SET LR6 CR0 ;;
INC LR4 128 ;;
chunk_loop:
MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
SET LR7 LR6 ;;
{% for i in range(3) %}
{{ subtract_digit() }}
{% if i < 2 %}ADD LR7 LR7 {{ cr.chunks }} ;;{% endif %}
{% endfor %}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_difference }}.L {{ cr.difference }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.difference }} LR0 ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_difference }}.L ; ACC.SUB.FIRST ;;
LD.MULT R0 LR8 {{ cr.digits }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
INC LR5 1 ; INC LR6 1 ;;
BLT.S LR6 {{ cr.chunks }} chunk_loop ;;
INC LR1 1 ; INC.MODP2 LR3 CR1 7 ;;
BEQ LR3 CR0 next_input_row ;;
BEQ LR0 CR0 next_token ;;
next_input_row:
INC LR2 1 ;;
next_token:
BLT.S LR1 {{ cr.tokens }} token_loop ;;
HALT ;;
