{#- Compare broadcast IDs against an exact radix-64 vocabulary ramp. -#}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0 ;;
SET LR3 CR0 ; SET LR5 CR0 ;;
token_loop:
SET LR4 CR0 ; SET LR6 CR0 ;;
LD.MULT R1 LR2 {{ cr.in0 }} ;;
ADD LR8 LR3 LR7 ;;
chunk_loop:
MULT.EE LR8 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST ;;
{% macro subtract() %}
LD.MULT R0 LR6 {{ cr.ramp }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.SUB ; INC LR6 1 ;;
{% endmacro %}
{% for p in range(3) %}
{{ subtract() }}
{% endfor %}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_delta }}.L {{ cr.delta }} LR0 ;;
LD.MULT.CYCLIC LR0 {{ cr.delta }} LR0 ;;
LD.MULT R0 LR0 {{ cr.ones }} ;;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_delta }}.L ; ACC.SUB ;;
INC LR4 1 ;;
BLT.S LR4 LR10 full_store ;;
ACTIVATE.QUANTIZE relu {{ cr.last }}.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
INC LR1 1 ;;
BEQ CR0 CR0 token_next ;;
full_store:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
INC LR1 1 ;;
BLT.S LR4 LR10 chunk_loop ;;
token_next:
INC.MODP2 LR3 CR1 7 ; INC LR5 1 ;;
BLT.S LR3 CR1 next_input_row ;;
BLT.S LR5 LR11 token_loop ;;
HALT ;;
next_input_row:
INC LR2 1 ;;
BLT.S LR5 LR11 token_loop ;;
HALT ;;
