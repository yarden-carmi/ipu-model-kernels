{# Equality via positive and negative differences. #}
{% macro difference(first, subsequent) %}
MULT.EE LR1 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; {{ first }} ;;
{% for base in ['ramp', 'mid', 'low'] %}
LD.MULT.CYCLIC LR2 {{ cr[base] }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; {{ subsequent }} ;;
{% endfor %}
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR3 CR0 ;;
SET LR4 CR0 ; SET LR6 CR0 ;;
token_loop:
LD.MULT R0 LR4 {{ cr.in0 }} ;;
SET LR2 CR0 ;;
chunk_loop:
{{ difference('ACC.ADD.FIRST', 'ACC.SUB') }}
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0 ;;
{{ difference('ACC.SUB.FIRST', 'ACC.ADD') }}
SET LR5 CR1 ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR5 ;;
LD.MULT.CYCLIC LR0 {{ cr.ones }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST ;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
LD.MULT.CYCLIC LR5 {{ cr.tmp }} LR0 ;;
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB ;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3 ;;
INC LR2 1 ; INC LR3 1 ;;
BLT.S LR2 {{ cr.chunks }} chunk_loop ;;
INC LR6 1 ;;
BGE.S LR6 {{ cr.tokens }} finish ;;
INC.MODP2 LR1 CR1 7 ;;
BNE LR1 CR0 token_loop ;;
INC LR4 1 ;;
BEQ LR0 CR0 token_loop ;;
finish:
HALT ;;
