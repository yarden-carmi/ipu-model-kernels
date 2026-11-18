SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0;;
SET LR3 CR0 ; SET LR4 CR0;;
row:
LD.MULT R0 LR1 {{ cr.in0 }};;
SET LR5 CR0 ; SET LR8 CR0;;
chunk:
MULT.EE LR2 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
SET LR6 CR0;;
INC LR6 128;;
{% macro subtract_limb() %}
LD.MULT R1 LR8 {{ cr.indices }};;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_indices }}.L ; ACC.SUB;;
INC LR8 1;;
{% endmacro %}
{% for k in range(4) %}
{{ subtract_limb() }}
{% endfor %}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_diff }}.L {{ cr.diff }} LR0;;
LD.MULT.CYCLIC LR0 {{ cr.diff }} LR0;;
LD.MULT R1 LR0 {{ cr.ones }};;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_diff }}.L ; ACC.SUB;;
MULT.EE LR0 CR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.MAX;;
INC LR5 1;;
BLT.S LR5 {{ cr.chunks }} full;;
ACTIVATE.QUANTIZE identity {{ cr.last }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3;;
BEQ LR0 CR0 stored;;
full:
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3;;
stored:
INC LR3 1;;
BLT.S LR5 {{ cr.chunks }} chunk;;
INC.MODP2 LR2 CR1 7 ; INC LR4 1;;
BNE LR2 CR0 next_row;;
INC LR1 1;;
next_row:
BLT.S LR4 {{ cr.tokens }} row;;
HALT;;
