{% macro diff(sign) %}
LD.MULT R0 LR1 {{ cr.in0 }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.{{ 'ADD' if sign == 1 else 'SUB' }}.FIRST;;
{% for i in range(3) %}
LD.MULT R0 LR3 {{ cr.digits }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_digits }}.L ; ACC.{{ 'SUB' if sign == 1 else 'ADD' }};;
INC LR3 1;;
{% endfor %}
{% endmacro %}
SET LR0 CR0;;
SET LR1 CR0;;
SET LR2 CR0;;
chunk:
SET LR4 CR0;;
SET LR3 CR0;;
vocab_loop:
{{ diff(1) }}
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR0;;
DEC LR3 3;;
{{ diff(-1) }}
SET LR5 CR1;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_tmp }}.L {{ cr.tmp }} LR5;;
LD.MULT R0 LR0 {{ cr.ones }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_ones }}.L ; ACC.ADD.FIRST;;
LD.MULT R0 LR0 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB;;
LD.MULT R0 LR5 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_tmp }}.L ; ACC.SUB;;
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR2;;
ADD LR2 LR2 {{ cr.chunks }} ; INC LR4 1;;
BLT.S LR4 {{ cr.vocab }} vocab_loop;;
INC LR1 1;;
SET LR2 LR1;;
BLT.S LR1 {{ cr.chunks }} chunk;;
HALT;;
