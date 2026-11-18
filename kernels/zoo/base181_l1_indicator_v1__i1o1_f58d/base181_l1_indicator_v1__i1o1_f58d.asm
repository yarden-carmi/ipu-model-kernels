{% macro ramp(upper) %}
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.EE LR2 {{ cr.gain }} 0 LR0 {{ cr.full }}.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
SET LR4 LR5;;
{% for k in range(3) %}
LD.MULT R0 LR4 {{ cr.digits }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_digits }}.L ; ACC.SUB;;
ADD LR4 LR4 {{ cr.chunks }};;
{% endfor %}
LD.MULT R0 LR7 {{ cr.digits }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_digits }}.L ; ACC.ADD;;
{% if upper %}
SET LR4 LR7;;
INC LR4 1;;
LD.MULT R0 LR4 {{ cr.digits }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_digits }}.L ; ACC.SUB;;
{% endif %}
ACTIVATE.QUANTIZE relu6 {{ cr.full }}.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR9;;
{% endmacro %}
SET LR0 CR0;;
SET LR1 CR0;;
SET LR2 CR0;;
SET LR3 CR0;;
SET LR6 CR0;;
SET LR8 CR1;;
{% for k in range(7) %}
ADD LR8 LR8 LR8;;
{% endfor %}
SET LR7 {{ cr.ones_offset }};;
token:
SET LR5 CR0;;
chunk:
SET LR9 CR0;;
{{ ramp(false) }}
INC LR9 1;;
{{ ramp(true) }}
LD.MULT R0 LR0 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.ADD.FIRST;;
LD.MULT R0 LR9 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_tmp }}.L ; ACC.SUB;;
INC LR4 1;;
LD.MULT R0 LR4 {{ cr.digits }};;
MULT.VE LR0 CR1 0 LR0 {{ cr.full }}.L {{ cr.qf_digits }}.L ; ACC.SUB;;
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
BLT.S LR2 LR8 next_token;;
SET LR2 CR0 ; INC LR1 1;;
next_token:
BLT.S LR6 {{ cr.tokens }} token;;
HALT;;
