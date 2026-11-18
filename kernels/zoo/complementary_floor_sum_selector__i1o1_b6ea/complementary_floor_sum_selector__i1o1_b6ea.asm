SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0;;
SET LR3 CR0 ; SET LR4 CR0 ; SET LR7 CR0;;
INC LR7 1;;
LD.MULT.CYCLIC LR7 {{ cr.ones }} LR0;;
SET LR9 CR0;;
INC LR9 128;;
row:
LD.MULT R0 LR1 {{ cr.in0 }};;
SET LR5 CR0;;
SET LR8 CR0;;
chunk:
SET LR6 CR0;;
INC LR6 128;;
{% macro limb(sign, base) %}
LD.MULT R1 LR8 {{ base }};;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_indices }}.L ; ACC.{{ sign }};;
INC LR8 1;;
{% endmacro %}
MULT.RC.VE LR0 LR2 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB.FIRST;;
{% for k in range(4) %}
{{ limb('ADD', cr.indices) }}
{% endfor %}
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_out0 }}.L {{ cr.diff }} LR0;;
MULT.RC.VE LR0 LR2 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
{% for k in range(4) %}
{{ limb('SUB', cr.indices) }}
{% endfor %}
MULT.RC.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.SUB;;
LD.MULT R1 LR0 {{ cr.ones }};;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD;;
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_out0 }}.L {{ cr.diff }} LR7;;
MULT.VE LR6 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST;;
LD.MULT.CYCLIC LR0 {{ cr.diff }} LR9;;
MULT.RC.VE LR9 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB;;
LD.MULT.CYCLIC LR7 {{ cr.diff }} LR9;;
MULT.RC.VE LR9 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB;;
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
