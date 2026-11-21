{# Integer equality using a squared-distance indicator. #}
{% macro difference() %}
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
{% for d in range(3) %}
LD.MULT R1 LR2 {{ cr.ramp }};;
MULT.VE LR3 CR1 0 LR0 CR15.L {{ cr.qf_ramp }}.L ; ACC.SUB;;
INC LR2 1;;
{% endfor %}
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR2 CR0;;
SET LR3 CR0;;
INC LR3 128;;
SET LR4 CR0;;
vocab_loop:
SET LR1 CR0;;
token_loop:
SET LR5 LR2;;
{{ difference() }}
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0;;
LD.MULT.CYCLIC LR0 {{ cr.tmp }} LR0;;
LD.MULT R0 LR0 {{ cr.ones }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST;;
MULT.RC.VS LR0 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB;;
MULT.VE LR0 CR0 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.MAX;;
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4;;
SET LR2 LR5;;
INC LR4 1 ; INC LR1 1;;
BLT.S LR1 {{ cr.blocks }} token_loop;;
INC LR2 3;;
BLT.S LR2 {{ cr.ramprows }} vocab_loop;;
HALT;;
