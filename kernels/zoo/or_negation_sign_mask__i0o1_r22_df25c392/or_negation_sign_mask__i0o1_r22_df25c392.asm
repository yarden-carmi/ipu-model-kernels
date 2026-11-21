{% macro diff(sign) %}
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.RC.VE LR10 LR0 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST;;
{% for i in range(3) %}
LD.MULT R0 LR3 {{ cr.digits }};;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }};;
INC LR3 1;;
{% endfor %}
{% endmacro %}
SET LR0 CR0;;
LD.MULT.CYCLIC LR0 {{ cr.gain }} LR0;;
SET LR10 CR0;;
INC LR10 128;;
LD.MULT.CYCLIC LR0 {{ cr.gain }} LR10;;
SET LR1 CR0;;
SET LR2 CR0;;
token_loop:
SET LR4 CR0;;
SET LR3 CR0;;
vocab_loop:
{{ diff(1) }}
LD.MULT R0 LR4 {{ cr.ones }};;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.SUB;;
LD.MULT R0 LR0 {{ cr.epsilon }};;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_epsilon }}.L ; ACC.ADD;;
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0;;
DEC LR3 3;;
{{ diff(-1) }}
SET LR5 LR4;;
INC LR5 1;;
LD.MULT R0 LR5 {{ cr.epsilon }};;
MULT.RC.VV LR0 R0 0 LR0 CR15.L {{ cr.qf_epsilon }}.L ; ACC.SUB;;
SET LR5 CR1;;
ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR5;;
LD.MULT R0 LR4 {{ cr.ones }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST;;
LD.MULT R0 LR0 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB;;
LD.MULT R0 LR5 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB;;
BNE LR4 LR6 full_row;;
ACTIVATE.QUANTIZE relu CR15.H {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2;;
BEQ LR0 CR0 stored;;
full_row:
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2;;
stored:
INC LR2 1 ; INC LR4 1;;
BLT.S LR4 {{ lr.chunks }} vocab_loop;;
INC LR1 1;;
BLT.S LR1 {{ lr.tokens }} token_loop;;
HALT;;
