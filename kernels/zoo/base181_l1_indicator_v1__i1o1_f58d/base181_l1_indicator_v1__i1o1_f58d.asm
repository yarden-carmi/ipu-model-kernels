{% macro difference(sign) %}
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.EE LR2 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; {{ 'ACC.ADD.FIRST' if sign == 1 else 'ACC.SUB.FIRST' }};;
{% for k in range(3) %}
LD.MULT R0 LR4 {{ cr.digits }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_digits }}.L ; {{ 'ACC.SUB' if sign == 1 else 'ACC.ADD' }};;
ADD LR4 LR4 {{ cr.chunks }};;
{% endfor %}
{% endmacro %}
SET LR0 CR0;;
SET LR1 CR0;;
SET LR2 CR0;;
SET LR3 CR0;;
SET LR6 CR0;;
SET LR7 {{ cr.ones_offset }};;
SET LR8 {{ cr.index128 }};;
token:
SET LR5 CR0;;
chunk:
SET LR4 LR5;;
{{ difference(1) }}
ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0;;
SET LR4 LR5;;
{{ difference(-1) }}
LD.MULT R0 LR0 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.MAX;;
ACTIVATE.QUANTIZE identity {{ cr.full }}.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0;;
LD.MULT R0 LR0 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.SUB.FIRST;;
LD.MULT R1 LR7 {{ cr.digits }};;
MULT.VE LR8 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_digits }}.L ; ACC.ADD;;
INC LR5 1;;
BLT.S LR5 {{ cr.chunks }} full_store;;
ACTIVATE.QUANTIZE relu {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3;;
BEQ LR0 CR0 stored;;
full_store:
ACTIVATE.QUANTIZE relu {{ cr.full }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR3;;
stored:
INC LR3 1;;
BLT.S LR5 {{ cr.chunks }} chunk;;
INC LR2 1 ; INC LR6 1;;
BLT.S LR2 {{ cr.index128 }} next_token;;
SET LR2 CR0 ; INC LR1 1;;
next_token:
BLT.S LR6 {{ cr.tokens }} token;;
HALT;;
