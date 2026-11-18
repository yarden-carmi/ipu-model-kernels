{# Fixed-address comparison of the two packed ID limbs. #}
token_loop:
LD.MULT R0 LR4 {{ cr.in0 }} ;;
SET LR5 CR0 ; SET LR6 CR0 ;;
chunk_loop:
{% macro difference(part) %}
LD.MULT R1 LR6 {{ cr.indices }} ;;
MULT.VE LR8 CR1 0 LR0 {{ cr.fullds }}.L {{ cr.qf_indices }}.L ; ACC.ADD.FIRST ;;
{% if part == 0 %}
MULT.EE LR3 CR1 0 LR0 {{ cr.fullds }}.L {{ cr.qf_in0 }}.L ; ACC.SUB ;;
{% endif %}
ACTIVATE.QUANTIZE identity {{ cr.fullds }}.L {{ cr.qf_diff }}.L {{ cr.diff }} LR7 ;;
INC LR6 1 ; INC LR7 1 ;;
{% endmacro %}
SET LR7 CR0 ;;
{{ difference(0) }}
{{ difference(1) }}
LD.MULT.CYCLIC LR0 {{ cr.diff }} LR0 ;;
SET LR7 CR1 ;;
LD.MULT.CYCLIC LR7 {{ cr.diff }} LR8 ;;
MULT.RC.VS LR0 0 LR0 {{ cr.fullds }}.L {{ cr.qf_diff }}.L ; ACC.SUB.FIRST ;;
MULT.RC.VS LR8 0 LR0 {{ cr.fullds }}.L {{ cr.qf_diff }}.L ; ACC.SUB ;;
LD.MULT R1 LR0 {{ cr.ones }} ;;
MULT.VE LR8 CR1 0 LR0 {{ cr.fullds }}.L {{ cr.qf_ones }}.L ; ACC.ADD ;;
INC LR5 1 ;;
BLT.S LR5 {{ cr.chunks }} full_store ;;
ACTIVATE.QUANTIZE relu {{ cr.endds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
INC LR1 1 ;;
INC LR3 1 ; INC LR2 1 ;;
BLT.S LR3 LR8 same_row ;;
SET LR3 CR0 ; INC LR4 1 ;;
same_row:
BLT.S LR2 {{ cr.tokens }} token_loop ;;
HALT ;;
full_store:
ACTIVATE.QUANTIZE relu {{ cr.fullds }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR1 ;;
INC LR1 1 ;;
BEQ LR0 CR0 chunk_loop ;;
