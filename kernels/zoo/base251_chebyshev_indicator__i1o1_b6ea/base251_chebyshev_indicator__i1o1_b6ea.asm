{% macro subtract_digit() %}
LD.MULT R0 LR7 {{ cr.digits }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.SUB ;;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR5 CR0 ;;
SET LR14 {{ cr.chunks }} ;;
DEC LR14 1 ;;
SET LR15 CR0 ;;
INC LR15 2 ;;
BLT.S LR15 {{ cr.chunks }} init_done ;;
SET LR15 {{ cr.chunks }} ;;
init_done:
NOP ;;
token_loop:
LD.MULT R1 LR2 {{ cr.in0 }} ;;
SET LR4 LR3 ; SET LR6 CR0 ;;
INC LR4 128 ;;
chunk_loop:
{# Inputs are bounded by 255; higher vocabulary indices are unequal. #}
SET LR9 CR0 ;;
INC LR9 2 ;;
BLT.S LR6 LR9 compute ;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.ADD.FIRST ;;
BEQ LR0 CR0 write_result ;;
compute:
MULT.EE LR4 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
SET LR7 LR6 ;;
{% for i in range(4) %}
{{ subtract_digit() }}
{% if i < 3 %}ADD LR7 LR7 LR15 ;;{% endif %}
{% endfor %}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_difference }}.L {{ cr.difference }} LR0 ;;
{% macro clamp_side(side) %}
LD.MULT.CYCLIC LR0 {{ cr.difference }} LR0 ;;
SET LR7 CR0 ;;
LD.MULT R0 LR7 {{ cr.controls }} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_difference }}.L ; ACC.ADD.FIRST ;;
{% if side == 0 %}
SET LR7 LR6 ;;
INC LR7 10 ;;
LD.MULT R0 LR7 {{ cr.controls }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_controls }}.L ; ACC.ADD ;;
{% endif %}
{% if side == 1 %}
INC LR7 2 ;;
LD.MULT R0 LR7 {{ cr.controls }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_controls }}.L ; ACC.ADD ;;
{% endif %}
SET LR7 CR1 ;;
LD.MULT R0 LR7 {{ cr.controls }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_controls }}.L ; ACC.ADD ;;
SET LR7 CR0 ;;
INC LR7 {{ side + 1 }} ;;
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_difference }}.L {{ cr.difference }} LR7 ;;
{% endmacro %}
{% for side in range(2) %}
{{ clamp_side(side) }}
{% endfor %}
SET LR7 CR1 ;;
LD.MULT.CYCLIC LR7 {{ cr.difference }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_difference }}.L ; ACC.ADD.FIRST ;;
INC LR7 1 ;;
LD.MULT.CYCLIC LR7 {{ cr.difference }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_difference }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_difference }}.L {{ cr.difference }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.difference }} LR0 ;;
SET LR7 CR0 ;;
INC LR7 3 ;;
{% macro normalize_term(term) %}
LD.MULT R0 LR7 {{ cr.controls }} ;;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_difference }}.L ; ACC.ADD{% if term == 0 %}.FIRST{% endif %} ;;
INC LR7 1 ;;
{% endmacro %}
{% for term in range(6) %}
{{ normalize_term(term) }}
{% endfor %}
LD.MULT R0 LR7 {{ cr.controls }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_controls }}.L ; ACC.ADD ;;
write_result:
BEQ LR6 LR14 tail_store ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
BEQ LR0 CR0 stored ;;
tail_store:
ACTIVATE.QUANTIZE relu {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR5 ;;
stored:
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
