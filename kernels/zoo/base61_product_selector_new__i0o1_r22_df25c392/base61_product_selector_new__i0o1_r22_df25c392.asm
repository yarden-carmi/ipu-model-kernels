{# Fixed-address interval indicators. #}
{% set g = cr.gain32 if format == 'fp32' else cr.gain %}
{% macro step(dest) %}
LD.MULT R0 LR3 {{ cr.hi }};;
MULT.EE LR12 {{ g }} 0 LR0 CR15.L {{ cr.qf_in0 }}.L ; ACC.ADD.FIRST;;
MULT.VE LR0 {{ g }} 0 LR0 CR15.L {{ cr.qf_hi }}.L ; ACC.SUB;;
LD.MULT R0 LR3 {{ cr.lo }};;
MULT.VE LR0 {{ g }} 0 LR0 CR15.L {{ cr.qf_lo }}.L ; ACC.SUB;;
ADD LR7 LR3 LR9;;
LD.MULT R0 LR7 {{ cr.lo }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_lo }}.L ; ACC.ADD ; ACTIVATE.QUANTIZE relu6 CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} LR0;;
LD.MULT R0 LR0 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST;;
LD.MULT R0 LR8 {{ cr.lo }};;
{% for i in range(5) %}
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_lo }}.L ; ACC.SUB;;
{% endfor %}
ACTIVATE.QUANTIZE relu CR15.L {{ cr.qf_out0 }}.L {{ cr.tmp }} {{ dest }};;
{% endmacro %}
SET LR0 CR0 ; SET LR1 CR0 ; SET LR4 CR0;;
SET LR5 CR1;;
ADD LR6 LR5 CR1;;
ADD LR9 LR11 LR11;;
ADD LR8 LR9 LR9;;
token:
LD.MULT R1 LR1 {{ cr.in0 }};;
SET LR2 CR0;;
chunk:
ADD LR3 LR2 CR0;;
{{ step('LR5') }}
ADD LR3 LR2 LR11;;
{{ step('LR6') }}
LD.MULT R0 LR5 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.ADD.FIRST;;
LD.MULT R0 LR6 {{ cr.tmp }};;
MULT.VE LR0 CR1 0 LR0 CR15.L {{ cr.qf_out0 }}.L ; ACC.SUB;;
BNE LR2 LR15 full_store;;
ACTIVATE.QUANTIZE identity {{ cr.tail }}.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4;;
BEQ LR0 CR0 stored;;
full_store:
ACTIVATE.QUANTIZE identity CR15.L {{ cr.qf_out0 }}.L {{ cr.out0 }} LR4;;
stored:
INC LR2 1 ; INC LR4 1;;
BLT.S LR2 LR11 chunk;;
INC LR1 1;;
BLT.S LR1 LR10 token;;
HALT;;
