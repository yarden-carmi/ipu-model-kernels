SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR7 CR0 ; SET LR10 CR1 ;;
token_loop:
SET LR4 CR0 ;;
chunk_loop:
SET LR11 LR4 ;;
{% macro step(which) %}
LD.MULT R0 LR1 {{ cr.in0 }} ;;
LD.MULT.CYCLIC LR0 {{ cr.gain }} LR0 ;;
MULT.RC.VE LR0 LR2 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% for p in range(3) %}
LD.MULT R0 LR11 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.SUB ;;
ADD LR11 LR11 {{ cr.chunks }} ;;
{% endfor %}
SET LR9 {{ cr.unitrow }} ;;
LD.MULT R0 LR9 {{ cr.idx }} ;;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_idx }}.L ; ACC.ADD ;;
ACTIVATE.QUANTIZE relu6 {{ cr.full }}.L {{ cr.qf_tmp }}.L {{ cr.tmp }} {{ which }} ;;
{% endmacro %}
{{ step('LR0') }}
{{ step('LR10') }}
LD.MULT R0 LR10 {{ cr.gain }} ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.ADD.FIRST ;;
LD.MULT.CYCLIC LR10 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 LR0 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.SUB ;;
INC LR4 1 ;;
BNE LR4 {{ cr.chunks }} full_store ;;
ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
BEQ LR0 CR0 stored ;;
full_store:
ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
stored:
INC LR3 1 ;;
BLT.S LR4 {{ cr.chunks }} chunk_loop ;;
INC LR7 1 ; INC.MODP2 LR2 CR1 7 ;;
BNE LR2 CR0 same_input_row ;;
INC LR1 1 ;;
same_input_row:
BLT.S LR7 {{ cr.tokens }} token_loop ;;
HALT ;;
